-- Guild Ranks: guild sync over hidden addon messages (guild channel only, so
-- data never leaves the guild). Numbers are sent in base 36 to keep messages short.
--   D;proto;class;level;version;YYYY-MM-DD;f1,f2,...[;flags[;title]]   one day of the sender's stats
--   A;proto;class;level;version;f1,f2,...[;flags[;title]]              the sender's all-time stats
--                                                       flags: "p" = hide my play time
--                                                       title: the weekly title the sender shows
--   R;proto;full|quick                                  "please send me your data"
--   L;proto                                             "I'm relaying offline members' data"
--   X;proto;player;class;level;version;day;f1,...[;flags[;title]]  relayed day for an offline member
--   C;proto;ver;resetDay;minMin;goldMask;mgrRank;spoon;itemValue;by;challengeMetric;prize;goalMetric;goalTarget;announceMVP;resetHour;showPlaytime
--                                                       guild rules (managers)
--   E;proto;ver;part;parts;name,name,...                excluded players (managers)
--   H;proto                                             "stop showing my stats"
--   W;proto;YYYY-MM-DD                                  "I announced this week's MVP in guild chat"
local ADDON, ns = ...
local L = ns.L
local C = {}
ns.Comm = C

local FULL_DAYS = 8            -- days sent for a full request
local RELAY_COOLDOWN = 90      -- a member relays at most once every 90 seconds (duplicates merge in the queue)
local RELAY_MAX = 80           -- most messages in one relay (big guilds)
local SEND_INTERVAL = 1.1      -- Blizzard allows ~1 addon message per second per prefix

local queue, queued = {}, {}
local pendingRules = {}        -- rule messages that arrived before the roster (sender rank unknown)
local lastAnswer = { full = -1000, quick = -1000 }
local lastRelay, relayClaimSeenAt = -10000, -1000
local lastSentDay
C.lastReceived = nil

-- Sync timing for /granks diag
local stats = {
	sent = 0, received = 0, relayed = 0,
	batchStart = nil, batchCount = 0, lastBatch = nil,   -- our own sending
	full = nil, lastFull = nil,                           -- our last full sync request
}
C.stats = stats

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
end

local function split(s, sep)
	local t = {}
	for part in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = part end
	return t
end

---------------------------------------------------------------------------
-- Base 36 numbers (safe for large totals)
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
	n = math.floor((n or 0) + 0.5)
	if n <= 0 then return "0" end
	local t = {}
	while n > 0 do
		local r = n % 36
		t[#t + 1] = DIGITS:sub(r + 1, r + 1)
		n = math.floor(n / 36)
	end
	return string.reverse(table.concat(t))
end

local function d36(s)
	if not s or s == "" then return nil end
	local n = 0
	for i = 1, #s do
		local c = s:byte(i)
		local v = (c <= 57) and (c - 48) or (c - 87)
		if v < 0 or v > 35 then return nil end
		n = n * 36 + v
	end
	return n
end
C.b36, C.d36 = b36, d36

local function EncodeBucket(b)
	local out = {}
	for i, f in ipairs(ns.FIELDS) do out[i] = b36(math.max(0, b[f] or 0)) end
	-- trailing zeros can be dropped
	local n = #out
	while n > 1 and out[n] == "0" do out[n] = nil; n = n - 1 end
	return table.concat(out, ",")
end

local function DecodeBucket(s)
	local vals = split(s or "", ",")
	local b = {}
	for i, f in ipairs(ns.FIELDS) do
		local n = d36(vals[i])
		if n and n > 0 and n < 1e14 then b[f] = n end
	end
	return b
end

---------------------------------------------------------------------------
-- Send queue (paused inside instances, where addon chat is restricted)
---------------------------------------------------------------------------
local function Enqueue(key, msg)
	if #queue == 0 then stats.batchStart, stats.batchCount = GetTime(), 0 end
	if not queued[key] then queue[#queue + 1] = key end
	queued[key] = { msg = msg, tries = 0 }
end

function C.QueueLength() return #queue end

-- For other modules: send a message (key: a later message with the same key replaces it in the queue),
-- handle a message kind, and add extra messages whenever our own stats are sent
C.Enqueue = Enqueue
C.handlers = {}         -- kind -> function(g, sender, parts)
C.extraSenders = {}     -- functions called when our all-time stats are queued

function C.ClearQueue()
	queue, queued = {}, {}
end

local function CanSend()
	local g = ns.G()
	if not g or g.solo or not IsInGuild() then return false end
	if C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and locked then return false end
	end
	if IsInInstance() then return false end
	return true
end
C.CanSend = CanSend

-- What we sent recently: our own messages come back with the name guildmates see for us
local recentSent, recentOrder = {}, {}
local function NoteSent(msg)
	if not recentSent[msg] then
		recentOrder[#recentOrder + 1] = msg
		if #recentOrder > 30 then recentSent[table.remove(recentOrder, 1)] = nil end
	end
	recentSent[msg] = GetTime()
end

local function SendNow(msg)
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, "GUILD")
	local sent = ok and res ~= false and not (type(res) == "number" and res ~= 0)
	if sent then NoteSent(msg) end
	return sent
end

-- Our own message coming back under a longer name ("Healya Jamie" when UnitName says "Healya")?
local function IsMyEcho(sender, text)
	local kind = text:sub(1, 2)
	if kind ~= "D;" and kind ~= "A;" then return false end -- only our own stats are unique to us
	local at = recentSent[text]
	if not at or GetTime() - at > 30 or not ns.me then return false end
	local first = ns.me:match("^(%S+)")
	return first ~= nil and sender:match("^(%S+)") == first
end

local function Pump()
	if #queue == 0 or not CanSend() then return end
	local key = table.remove(queue, 1)
	local item = queued[key]
	queued[key] = nil
	if not item then return end
	if SendNow(item.msg) then
		stats.sent, stats.batchCount = stats.sent + 1, stats.batchCount + 1
		stats.lastSent = time()
		local f = stats.full
		if key == "R" and item.msg:find("full", 1, true) and not (f and GetTime() - (f.last or f.start) < 15) then
			stats.full = { start = GetTime(), at = time(), msgs = 0, from = {}, members = 0 }
		end
		if #queue == 0 and stats.batchStart then
			stats.lastBatch = { n = stats.batchCount, secs = GetTime() - stats.batchStart, at = time() }
			stats.batchStart = nil
		end
	elseif item.tries < 3 and not queued[key] then
		item.tries = item.tries + 1
		table.insert(queue, 1, key)
		queued[key] = item
	end
end

-- Seconds until everything waiting has been sent (one message per interval)
function C.SecondsToSend()
	return #queue * SEND_INTERVAL
end

-- Count data arriving after our full sync request (finished when quiet for 15 s)
local function NoteData(sender)
	stats.received = stats.received + 1
	local f = stats.full
	if f and GetTime() - f.start < 600 then
		f.msgs = f.msgs + 1
		if not f.from[sender] then f.from[sender] = true; f.members = f.members + 1 end
		f.last = GetTime()
	end
end

-- Last full sync: seconds it took, messages, members, still arriving?
function C.FullSyncInfo()
	local f = stats.full
	if not f then return nil end
	local busy = (GetTime() - (f.last or f.start)) < 15
	return { secs = (f.last or f.start) - f.start, msgs = f.msgs, members = f.members, busy = busy, at = f.at }
end

---------------------------------------------------------------------------
-- What we send
---------------------------------------------------------------------------
local function Header(kind, p)
	return string.format("%s;%d;%s;%d;%s", kind, ns.PROTO, p.class or "", p.level or 0, ns.VERSION)
end

-- Optional flags at the end of D/A messages (left out when empty, to save space)
local function Flags()
	local hide = ns.db.showPlay == false
	local title = ns.Personal and ns.Personal.MyTitleCode()
	if title then return ";" .. (hide and "p" or "") .. ";" .. title end
	return hide and ";p" or ""
end

local function ValidTitle(s)
	return type(s) == "string" and #s <= 12 and s:match("^[a-z]+$") and s or nil
end

local function Me()
	local g = ns.G()
	return g, g and ns.GetPlayer(g, ns.me)
end

function C.QueueDay(day)
	if not ns.db.share then return end
	local g, p = Me()
	if not p or not p.days[day] then return end
	Enqueue("D" .. day, Header("D", p) .. ";" .. day .. ";" .. EncodeBucket(p.days[day]) .. Flags())
end

function C.QueueAll()
	if not ns.db.share then return end
	local g, p = Me()
	if not p then return end
	Enqueue("A", Header("A", p) .. ";" .. EncodeBucket(p.all) .. Flags())
	for _, fn in ipairs(C.extraSenders) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

function C.QueueRecent(days)
	local today = ns.Today()
	for i = (days or FULL_DAYS) - 1, 0, -1 do C.QueueDay(ns.ShiftDay(today, -i)) end
	C.QueueAll()
	lastSentDay = today
end

function C.Request(mode)
	Enqueue("R", "R;" .. ns.PROTO .. ";" .. (mode or "quick"))
end

local function GoldMask(r)
	local m = {}
	for i, src in ipairs(ns.GOLD_SOURCES) do m[i] = r.gold[src] and "1" or "0" end
	return table.concat(m)
end

function C.QueueRules()
	local g = ns.G()
	if not g or g.solo then return end
	local r = g.rules
	if (r.version or 0) <= 0 then return end
	Enqueue("C", string.format("C;%d;%s;%d;%d;%s;%d;%d;%s;%s;%s;%s;%s;%s;%d", ns.PROTO, b36(r.version), r.resetDay,
		r.minMinutes, GoldMask(r), r.managerRank or 1, r.showSpoon and 1 or 0, r.itemValue == "auction" and "a" or "v",
		r.by or "", r.challengeMetric or "", ns.CleanText(r.challengePrize or "", 40), r.goalMetric or "",
		b36(r.goalTarget or 0), r.announceMVP and 1 or 0) .. string.format(";%d;%d;%d", ns.ResetHour(g),
		r.showPlaytime == false and 0 or 1, r.inactiveDays or 14))
	-- Excluded players, in chunks that fit in a message
	local names, parts, cur = {}, {}, {}
	for name in pairs(r.excluded) do names[#names + 1] = name end
	table.sort(names)
	local len = 0
	for _, name in ipairs(names) do
		if len + #name > 200 then
			parts[#parts + 1] = table.concat(cur, ",")
			cur, len = {}, 0
		end
		cur[#cur + 1] = name
		len = len + #name + 1
	end
	parts[#parts + 1] = table.concat(cur, ",")
	for i, chunk in ipairs(parts) do
		Enqueue("E" .. i, string.format("E;%d;%s;%d;%d;%s", ns.PROTO, b36(r.version), i, #parts, chunk))
	end
end

-- Called by the settings screen when a manager saves the rules
function C.PublishRules()
	local g = ns.G()
	if not g then return end
	g.rules.version = GetServerTime()
	g.rules.excludedFor = g.rules.version
	g.rules.by = ns.ShortName(ns.me)
	C.QueueRules()
end

-- Pass along recent days we hold for members who are offline right now
function C.QueueRelay(requester)
	local g = ns.G()
	if not g then return 0 end
	local online = {}
	for name, info in pairs(ns.roster) do
		if info.online then online[name] = true end
	end
	local today = ns.Today()
	local oldest = ns.ShiftDay(today, -(FULL_DAYS - 1))
	local items = {}
	for key, p in pairs(g.players) do
		if key ~= ns.me and key ~= requester and not online[key] and not g.hidden[key] then
			for day, b in pairs(p.days) do
				if day >= oldest and day <= today and (b.playtime or 0) > 0 then
					items[#items + 1] = { key = key, p = p, day = day, b = b }
				end
			end
		end
	end
	table.sort(items, function(a, b) return a.day > b.day end) -- most recent first
	for i = 1, math.min(#items, RELAY_MAX) do
		local it = items[i]
		Enqueue("X" .. it.key .. it.day, string.format("X;%d;%s;%s;%d;%s;%s;%s%s", ns.PROTO, it.key,
			it.p.class or "", it.p.level or 0, it.p.version or "", it.day, EncodeBucket(it.b),
			it.p.title and (";" .. (it.p.hidePlay and "p" or "") .. ";" .. it.p.title) or (it.p.hidePlay and ";p" or "")))
	end
	return math.min(#items, RELAY_MAX)
end

-- Turn sharing on or off. Off: guildmates are asked to remove your stats.
-- Show or hide my play time from guildmates (tells them right away)
function C.SetShowPlay(on)
	ns.db.showPlay = on and true or false
	C.QueueDay(ns.Today())
	C.QueueAll()
end

function C.SetShare(on)
	ns.db.share = on and true or false
	C.ClearQueue()
	if on then
		C.QueueRecent()
	else
		Enqueue("H", "H;" .. ns.PROTO)
	end
end

-- One-off claim messages (e.g. "W" = this week's MVP was announced)
function C.SendClaim(kind, value)
	if CanSend() then SendNow(kind .. ";" .. ns.PROTO .. ";" .. tostring(value)) end
end

function C.SyncNow()
	C.Request("full")
	C.QueueRecent()
	if ns.CanEditRules() then C.QueueRules() end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function ValidDay(day)
	if not (day and day:match("^%d%d%d%d%-%d%d%-%d%d$")) then return false end
	local today = ns.Today()
	return day <= ns.ShiftDay(today, 1) and day >= ns.ShiftDay(today, -ns.KEEP_DAYS)
end

-- Returns the sender's rank, or nil + true if we can't tell yet (roster not loaded)
local function SenderRank(sender)
	local rank = ns.RankOfMember(sender)
	if rank then return rank end
	return nil, not ns.rosterReady or not ns.roster[sender]
end

local function HoldForRoster(kind, sender, parts)
	if #pendingRules < 30 then pendingRules[#pendingRules + 1] = { kind = kind, sender = sender, parts = parts } end
end

local ReceiveRules, ReceiveExcluded

ReceiveRules = function(g, sender, parts)
	local version = d36(parts[3])
	local resetDay, minMinutes = tonumber(parts[4]), tonumber(parts[5])
	if not (version and resetDay and minMinutes) then return end
	local r = g.rules
	if version <= (r.version or 0) then return end
	local rank, unknown = SenderRank(sender)
	if not rank then
		if unknown then HoldForRoster("C", sender, parts) end
		return
	end
	if rank > (r.managerRank or 1) then return end
	r.version = version
	r.resetDay = math.min(7, math.max(1, math.floor(resetDay)))
	r.minMinutes = math.max(0, math.floor(minMinutes))
	local mask = parts[6] or ""
	for i, src in ipairs(ns.GOLD_SOURCES) do r.gold[src] = (mask:sub(i, i) == "1") end
	if rank == 0 then r.managerRank = tonumber(parts[7]) or r.managerRank end -- only the GM changes this
	r.showSpoon = parts[8] ~= "0"
	r.itemValue = (parts[9] == "a") and "auction" or "vendor"
	r.by = (parts[10] and parts[10] ~= "") and parts[10] or ns.ShortName(sender)
	r.challengeMetric = (parts[11] and ns.METRIC_BY_KEY[parts[11]]) and parts[11] or nil
	r.challengePrize = (parts[12] and parts[12] ~= "") and parts[12] or nil
	r.goalMetric = (parts[13] and ns.METRIC_BY_KEY[parts[13]]) and parts[13] or nil
	r.goalTarget = d36(parts[14]) or 0
	r.announceMVP = parts[15] == "1"
	local hour = math.min(23, math.max(0, math.floor(tonumber(parts[16]) or 0)))
	if hour ~= (r.resetHour or 0) then
		r.resetHour = hour
		ns.InvalidateToday()
	end
	r.showPlaytime = parts[17] ~= "0"
	local inactive = tonumber(parts[18])
	if inactive and inactive >= 3 and inactive <= 90 then r.inactiveDays = math.floor(inactive) end
	r.excluded = {}
	r.excludedFor = version
	ns.Print(string.format(L["Guild rules updated by %s."], r.by))
	ns.MarkChanged()
end

ReceiveExcluded = function(g, sender, parts)
	local version = d36(parts[3])
	local r = g.rules
	if not version then return end
	local rank, unknown = SenderRank(sender)
	if not rank then
		if unknown then HoldForRoster("E", sender, parts) end
		return
	end
	if version ~= r.version or r.excludedFor ~= version then return end
	if rank > (r.managerRank or 1) then return end
	for name in (parts[6] or ""):gmatch("[^,]+") do
		local n = ns.CanonName(name)
		if n then r.excluded[n] = true end
	end
	ns.MarkChanged()
end

-- Called when the roster loads: apply rule messages we had to hold
function C.ProcessPending()
	if #pendingRules == 0 or not ns.rosterReady then return end
	local g = ns.G()
	local list = pendingRules
	pendingRules = {}
	if not g or g.solo then return end
	for _, item in ipairs(list) do
		if ns.RankOfMember(item.sender) then
			if item.kind == "C" then ReceiveRules(g, item.sender, item.parts) else ReceiveExcluded(g, item.sender, item.parts) end
		end
	end
end

-- Answer a "send me your data" request. Each member answers at most once a minute;
-- a request inside that minute is answered when the minute is up (not dropped), so
-- two members logging in close together both get the data.
local deferred = { full = false, quick = false }
function C.Answer(mode, sender)
	local requestAt = GetTime()
	local since = requestAt - lastAnswer[mode]
	if since <= 60 then
		if not deferred[mode] then
			deferred[mode] = true
			C_Timer.After(61 - since, function()
				deferred[mode] = false
				C.Answer(mode, sender)
			end)
		end
		return
	end
	lastAnswer[mode] = requestAt
	-- Refresh the roster first, so we know who is offline before relaying
	if mode == "full" then ns.RequestRoster() end
	C_Timer.After(2 + math.random() * 10, function()
		if mode == "quick" then
			C.QueueRecent(2)
			return
		end
		-- First member to answer also relays offline members' data ("L" claim)
		local relay = relayClaimSeenAt < requestAt and GetTime() - lastRelay > RELAY_COOLDOWN and CanSend()
		if relay then relay = SendNow("L;" .. ns.PROTO) end
		C.QueueRecent()
		if ns.CanEditRules() then C.QueueRules() end
		if relay then
			lastRelay = GetTime()
			C.QueueRelay(sender)
		end
	end)
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
	if prefix ~= ns.PREFIX or not ns.db then return end
	if not (ns.Readable(text) and ns.Readable(sender)) or channel ~= "GUILD" then return end
	local g = ns.G()
	if not g or g.solo then return end
	sender = ns.CanonName(sender)
	if not sender or sender == ns.me then return end
	if IsMyEcho(sender, text) then
		ns.RenameMe(sender) -- now we know the name guildmates see for us
		return
	end

	local parts = split(text, ";")
	local kind, proto = parts[1], tonumber(parts[2])
	if proto ~= ns.PROTO then return end

	if kind == "D" or kind == "A" then
		g.hidden[sender] = nil
		local p = ns.GetPlayer(g, sender, true)
		if parts[3] and parts[3] ~= "" then p.class = parts[3] end
		p.level = tonumber(parts[4]) or p.level
		p.version = parts[5]
		p.seen = time()
		if ns.NoteVersion then ns.NoteVersion(parts[5]) end
		if kind == "D" then
			if ValidDay(parts[6]) then p.days[parts[6]] = DecodeBucket(parts[7]) end
			p.hidePlay = parts[8] == "p" or nil
			p.title = ValidTitle(parts[9])
		else
			p.all = DecodeBucket(parts[6])
			p.hidePlay = parts[7] == "p" or nil
			p.title = ValidTitle(parts[8])
		end
		C.lastReceived = time()
		NoteData(sender)
		ns.MarkChanged()
	elseif kind == "R" then
		C.Answer(parts[3] == "full" and "full" or "quick", sender)
	elseif kind == "L" then
		relayClaimSeenAt = GetTime()
	elseif kind == "X" then
		local key, day = ns.CanonName(parts[3]), parts[7]
		if not key or key == ns.me or g.hidden[key] or not ValidDay(day) then return end
		local b = DecodeBucket(parts[8])
		local p = ns.GetPlayer(g, key, true)
		if parts[9] == "p" then p.hidePlay = true end -- only direct messages can clear these
		if ValidTitle(parts[10]) then p.title = parts[10] end
		stats.relayed = stats.relayed + 1
		NoteData(sender)
		p.relayedAt = time()
		local existing = p.days[day]
		if not existing or (b.playtime or 0) > (existing.playtime or 0) then
			p.days[day] = b
			if not p.class and parts[4] ~= "" then p.class = parts[4] end
			p.level = math.max(p.level or 0, tonumber(parts[5]) or 0)
			p.version = p.version or parts[6]
			ns.MarkChanged()
		end
	elseif kind == "C" then
		ReceiveRules(g, sender, parts)
	elseif kind == "E" then
		ReceiveExcluded(g, sender, parts)
	elseif kind == "W" then
		if parts[3] and parts[3]:match("^%d%d%d%d%-%d%d%-%d%d$") then g.announcedWeek = parts[3] end
	elseif kind == "H" then
		g.players[sender] = nil
		g.hidden[sender] = true
		ns.MarkChanged()
	elseif C.handlers[kind] then
		C.handlers[kind](g, sender, parts)
	end
end)

---------------------------------------------------------------------------
-- Schedule
---------------------------------------------------------------------------
ns.OnGuildChanged(function()
	C.ClearQueue()
	local g = ns.G()
	if not g or g.solo then return end
	C_Timer.After(10, function()
		if ns.G() ~= g then return end
		-- Full sync if we know few members or haven't done one today
		local known = 0
		for _ in pairs(g.players) do known = known + 1 end
		local full = known < 3 or (g.lastFull or 0) < time() - 86400
		if full then g.lastFull = time() end
		C.Request(full and "full" or "quick")
		C.QueueRecent(full and FULL_DAYS or 2)
		if ns.CanEditRules() then C.QueueRules() end
	end)
end)

ns.OnLogin(function()
	C_Timer.NewTicker(SEND_INTERVAL, Pump)
	-- Every 5 minutes: share today's numbers if they changed
	C_Timer.NewTicker(300, function()
		local st = ns.Tracker.state
		if not st.dirty then return end
		st.dirty = false
		local today = ns.Today()
		if lastSentDay and lastSentDay ~= today then C.QueueDay(lastSentDay) end
		C.QueueDay(today)
		C.QueueAll()
		lastSentDay = today
	end)
end)
