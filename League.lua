-- Guild Ranks: guild vs guild. Guilds compare "team sheets" (per category, the average per hour
-- of their top 5 players this league week). Sheets travel over a hidden public channel
-- ("GuildRanksLeague"), by whisper between rival guilds, and inside each guild. No member names
-- ever leave the guild. Officers challenge other guilds; an officer of the other guild accepts.
local ADDON, ns = ...
local L = ns.L
local G = {}
ns.League = G

G.CATS = { "gold", "levels", "damage", "healing", "quests", "kills", "gathers", "crafts" }
G.TOP_N, G.MIN_QUALIFIED, G.MAX_RIVALS = 5, 3, 5
G.CHANNEL = "GuildRanksLeague"
local BEACON_EVERY, STALE, QUERY_EVERY = 600, 1500, 600
-- values travel as whole numbers: copper/h, levels*1000/h, damage/healing per h, others *10 per h
local SCALE = { gold = 1, levels = 1000, damage = 1, healing = 1, quests = 10, kills = 10, gathers = 10, crafts = 10 }
-- anything above these (per hour) is not believable: the sheet is ignored
local CAPS = { gold = 5000000, levels = 10, damage = 50000000, healing = 50000000, quests = 300, kills = 5000, gathers = 2000, crafts = 3000 }

local channelId = 0          -- league channel number (0 = not joined / unavailable)
local lastOwnBeacon = -1e9   -- when our guild's sheet was last sent or heard (by anyone in the guild)
local lastQuery = {}         -- rival -> GetTime() of the last whisper query
local seenIds = {}           -- challenge ids already handled
local pendingIn = {}         -- id -> { from, contact, at } challenges waiting for one of our officers
local notFound = {}          -- names we whispered that turned out offline (to hide the system message)

local function b36(n)
	n = math.max(0, math.floor(n or 0))
	if n == 0 then return "0" end
	local digits, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""
	while n > 0 do
		local r = n % 36
		s = digits:sub(r + 1, r + 1) .. s
		n = math.floor(n / 36)
	end
	return s
end
local function d36(s) return tonumber(s or "", 36) end

local function Send(key, msg, chatType, target) ns.Comm.Enqueue(key, msg, chatType, target) end
local function Officer(g) return g and not g.solo and ns.CanEditRules(g) end
local function Hidden(g) return g and g.rules and g.rules.leagueHidden == true end

local function Data()
	ns.db.league = ns.db.league or {}
	ns.db.league.guilds = ns.db.league.guilds or {}
	return ns.db.league
end

local function Rivals(g)
	g.rivals = g.rivals or {}
	return g.rivals
end

-- League week: Wednesday to Wednesday (realm days) for every guild
function G.Week() return ns.WeekStart({ rules = { resetDay = 4 } }) end
function G.PrevWeek() return ns.ShiftDay(G.Week(), -7) end

---------------------------------------------------------------------------
-- Team sheets
---------------------------------------------------------------------------
function G.Sheet(g, week)
	week = week or G.Week()
	local range = { from = week, to = ns.ShiftDay(week, 7) }
	local vals = {}
	for i, cat in ipairs(G.CATS) do
		local rows = ns.BuildBoard(g, cat, range, true, 0)
		local sum, n = 0, 0
		for j = 1, math.min(G.TOP_N, #rows) do sum, n = sum + (rows[j].value or 0), n + 1 end
		vals[i] = n > 0 and sum / n or 0
	end
	local q, users = 0, 0
	local minSecs = math.max(60, (g.rules.minMinutes or 0) * 60)
	for _, p in pairs(ns.EligiblePlayers(g)) do
		users = users + 1
		if (ns.Aggregate(p, range, g).playtime or 0) >= minSecs then q = q + 1 end
	end
	return { week = week, vals = vals, q = q, users = users, at = time() }
end

local function EncodeSheet(guild, s)
	local v = {}
	for i, cat in ipairs(G.CATS) do v[i] = b36((s.vals[i] or 0) * SCALE[cat]) end
	return string.format("G;%d;b;%s;%s;%d;%d;%s", ns.PROTO, guild, s.week, s.q, s.users, table.concat(v, ","))
end

local function DecodeSheet(parts)
	local week, q, users = parts[5], tonumber(parts[6]), tonumber(parts[7])
	if not (week and week:match("^%d%d%d%d%-%d%d%-%d%d$") and q and users) then return nil end
	local vals, i = {}, 0
	for item in (parts[8] or ""):gmatch("[^,]+") do
		i = i + 1
		local cat = G.CATS[i]
		local n = d36(item)
		if not cat or not n then return nil end
		local v = n / SCALE[cat]
		if v > CAPS[cat] then return nil end -- not believable
		vals[i] = v
	end
	if i ~= #G.CATS or q < 0 or users < 0 or q > 1000 or users > 1000 then return nil end
	return { week = week, vals = vals, q = q, users = users }
end

-- Keep a guild's sheet (this week and last week only)
local function StoreSheet(name, s, contact)
	local d = Data()
	local e = d.guilds[name] or { weeks = {} }
	d.guilds[name] = e
	e.weeks = e.weeks or {}
	e.weeks[s.week] = { vals = s.vals, q = s.q, users = s.users, at = time() }
	e.seen = time()
	if contact then
		e.contacts = e.contacts or {}
		for i, c in ipairs(e.contacts) do if c == contact then table.remove(e.contacts, i) break end end
		table.insert(e.contacts, 1, contact)
		while #e.contacts > 3 do table.remove(e.contacts) end
	end
	local keep = { [G.Week()] = true, [G.PrevWeek()] = true }
	for week in pairs(e.weeks) do if not keep[week] then e.weeks[week] = nil end end
end

function G.TheirSheet(name, week)
	local e = Data().guilds[name]
	return e and e.weeks and e.weeks[week or G.Week()] or nil
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
-- Points for each guild (1 per category won, half for a tie) and the per-category detail
function G.Score(ours, theirs)
	if not ours or not theirs then return nil end
	local us, them, cats = 0, 0, {}
	for i, cat in ipairs(G.CATS) do
		local a, b = ours.vals[i] or 0, theirs.vals[i] or 0
		local res = (a > b and "win") or (a < b and "loss") or "tie"
		if res == "win" then us = us + 1 elseif res == "loss" then them = them + 1 else us, them = us + 0.5, them + 0.5 end
		cats[i] = { cat = cat, ours = a, theirs = b, result = res }
	end
	local valid = (ours.q or 0) >= G.MIN_QUALIFIED and (theirs.q or 0) >= G.MIN_QUALIFIED
	return { us = us, them = them, cats = cats, valid = valid }
end

function G.FormatPoints(n)
	if n % 1 == 0 then return tostring(math.floor(n)) end
	return string.format("%.1f", n)
end

-- Active rivals of guild g: { { name, info }, ... } by name
function G.ActiveRivals(g)
	local out = {}
	for name, r in pairs(Rivals(g)) do
		if r.since and not (r.ended and r.ended >= r.since) then out[#out + 1] = { name = name, info = r } end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function IsRival(g, name)
	local r = Rivals(g)[name]
	return r ~= nil and r.since ~= nil and not (r.ended and r.ended >= r.since)
end
G.IsRival = IsRival

-- "All guilds": everyone heard this week, with a power score (100 = best in every category)
function G.Directory(g)
	local week = G.Week()
	local list = {}
	local mine = G.Sheet(g, week)
	if not Hidden(g) then list[#list + 1] = { name = g.name, sheet = mine, own = true } end
	for name, e in pairs(Data().guilds) do
		local s = e.weeks and e.weeks[week]
		if s and name ~= g.name then list[#list + 1] = { name = name, sheet = s, seen = e.seen, rival = IsRival(g, name) } end
	end
	local best = {}
	for _, item in ipairs(list) do
		if item.sheet.q >= G.MIN_QUALIFIED then
			for i = 1, #G.CATS do best[i] = math.max(best[i] or 0, item.sheet.vals[i] or 0) end
		end
	end
	for _, item in ipairs(list) do
		if item.sheet.q >= G.MIN_QUALIFIED then
			local sum = 0
			for i = 1, #G.CATS do sum = sum + ((best[i] or 0) > 0 and (item.sheet.vals[i] or 0) / best[i] or 0) end
			item.power = math.floor(sum / #G.CATS * 100 + 0.5)
		end
	end
	table.sort(list, function(a, b)
		if (a.power or -1) ~= (b.power or -1) then return (a.power or -1) > (b.power or -1) end
		return a.name < b.name
	end)
	return list
end

---------------------------------------------------------------------------
-- Rival list (shared inside the guild; the newest change wins)
---------------------------------------------------------------------------
local function Stamp(r) return math.max(r.since or 0, r.ended or 0) end

local function QueueRivalList(g)
	local items = {}
	for name, r in pairs(Rivals(g)) do
		items[#items + 1] = string.format("%s:%d:%d", name, r.since or 0, r.ended or 0)
	end
	if #items == 0 then return end
	Send("Grv", string.format("G;%d;rv;%s", ns.PROTO, table.concat(items, ",")))
end
G.QueueRivalList = QueueRivalList

local function MergeRival(g, name, since, ended, contact)
	local r = Rivals(g)[name]
	local incoming = math.max(since or 0, ended or 0)
	if r and Stamp(r) >= incoming then return false end
	r = r or { record = { w = 0, l = 0, d = 0 }, history = {} }
	r.since, r.ended = (since and since > 0) and since or r.since, (ended and ended > 0) and ended or nil
	if contact then r.contact = contact end
	Rivals(g)[name] = r
	return true
end

table.insert(ns.Comm.extraSenders, function()
	local g = ns.G()
	if g and not g.solo then QueueRivalList(g) end
end)

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function SendBeacon(g, chatType, target, keySuffix)
	if Hidden(g) or not ns.db.share then return end
	local msg = EncodeSheet(g.name, G.Sheet(g))
	Send("Gb" .. (keySuffix or ""), msg, chatType, target)
end

-- Join the hidden league channel (and keep it out of the chat windows)
function G.JoinChannel()
	if ns.db.leagueChannel == false or not JoinTemporaryChannel then return false end
	pcall(JoinTemporaryChannel, G.CHANNEL)
	local id = GetChannelName and select(1, GetChannelName(G.CHANNEL)) or 0
	channelId = (type(id) == "number" and id > 0) and id or 0
	if channelId > 0 and ChatFrame_RemoveChannel then
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			local cf = _G["ChatFrame" .. i]
			if cf then pcall(ChatFrame_RemoveChannel, cf, G.CHANNEL) end
		end
	end
	return channelId > 0
end
function G.ChannelOK() return channelId > 0 and not (ns.Comm.lastDirectError and ns.Comm.lastDirectError.chatType == "CHANNEL"
	and GetTime() - ns.Comm.lastDirectError.at < 900) end

local function Broadcast(msg, key)
	if channelId > 0 then Send(key, msg, "CHANNEL", channelId) end
end

-- Hide "No player named X is currently playing" for names we whispered on the addon's behalf
local function InstallFilter()
	if not ChatFrame_AddMessageEventFilter then return end
	local gs = type(_G.ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and _G.ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
	local pattern = "^" .. gs:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, text)
		if type(text) ~= "string" or not ns.Readable(text) then return false end
		local who = text:match(pattern)
		if who and notFound[who] and GetTime() - notFound[who] < 10 then return true end
		return false
	end)
end

local function Whisper(key, msg, name)
	notFound[name] = GetTime()
	Send(key, msg, "WHISPER", name)
end

---------------------------------------------------------------------------
-- Challenges
---------------------------------------------------------------------------
local function NewId() return string.format("%x%02x", GetServerTime(), math.random(0, 255)) end

-- Challenge a guild we heard on the league channel (or, with byName, through one of its members)
function G.Challenge(name, byName)
	local g = ns.G()
	if not Officer(g) then return false, L["Only officers can challenge other guilds."] end
	if Hidden(g) then return false, L["Your guild is hidden from the league (Settings > Guild rules)."] end
	if #G.ActiveRivals(g) >= G.MAX_RIVALS then return false, string.format(L["You already have %d rival guilds."], G.MAX_RIVALS) end
	if not byName and (not name or name == g.name or IsRival(g, name)) then return false end
	local id = NewId()
	g.outgoing = g.outgoing or {}
	g.outgoing[id] = { to = name, at = time() }
	local msg = string.format("G;%d;c;%s;%s;%s;%s", ns.PROTO, id, g.name, name or "", "")
	Send("Gc" .. id, msg) -- tell our guild (so any member can complete it)
	if byName then
		Whisper("Gcw" .. id, string.format("G;%d;c;%s;%s;%s", ns.PROTO, id, g.name, ""), byName)
		ns.Print(string.format(L["Challenge sent to %s. An officer of their guild has to accept."], byName))
	else
		Broadcast(msg, "Gcc" .. id)
		ns.Print(string.format(L["Challenge sent to %s. One of their officers has to accept."], name))
	end
	return true
end

local function ShowInvite(g, id, from)
	if not Officer(g) or Hidden(g) then return end
	pendingIn[id] = pendingIn[id] or { from = from, at = GetTime() }
	if ns.UI and ns.UI.ShowLeagueInvite then ns.UI.ShowLeagueInvite(id, from) end
end

function G.Answer(id, yes)
	local g = ns.G()
	local inc = pendingIn[id]
	if not g or not inc or not Officer(g) then return false end
	pendingIn[id] = nil
	if ns.UI and ns.UI.HideLeagueInvite then ns.UI.HideLeagueInvite() end
	local msg = string.format("G;%d;a;%s;%s;%s;%s", ns.PROTO, id, inc.from, g.name, yes and "yes" or "no")
	Send("Ga" .. id, msg) -- our guild
	Broadcast(msg, "Gac" .. id)
	if inc.contact then Whisper("Gaw" .. id, msg, inc.contact) end
	if yes then
		MergeRival(g, inc.from, time(), nil, inc.contact)
		QueueRivalList(g)
		SendBeacon(g)
		if inc.contact then SendBeacon(g, "WHISPER", inc.contact, "w") end
		ns.Print(string.format(L["%s is now your rival guild. Weekly matches start this week."], inc.from))
	end
	ns.MarkChanged()
	return true
end
function G.PendingInvites() return pendingIn end

function G.EndRivalry(name)
	local g = ns.G()
	if not Officer(g) or not IsRival(g, name) then return false end
	local r = Rivals(g)[name]
	r.ended = time()
	local msg = string.format("G;%d;u;%s;%s", ns.PROTO, g.name, name)
	Send("Gu" .. name, msg)
	Broadcast(msg, "Guc" .. name)
	if r.contact then Whisper("Guw" .. name, msg, r.contact) end
	QueueRivalList(g)
	ns.MarkChanged()
	return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function OnlineOfficers(g)
	local out = {}
	for key, info in pairs(ns.roster) do
		if info.online and info.rankIndex and info.rankIndex <= (g.rules.managerRank or 1) and key ~= ns.me then out[#out + 1] = key end
	end
	table.sort(out)
	return out
end

local function Handle(g, sender, parts, channel, channelName)
	if channel == "CHANNEL" and not (type(channelName) == "string" and channelName:lower():find(G.CHANNEL:lower(), 1, true)) then return end
	local kind = parts[3]
	local fromOutside = channel ~= "GUILD"
	if kind == "b" then
		local name = parts[4]
		local s = name and DecodeSheet(parts)
		if not s then return end
		if name == g.name then
			if s.week == G.Week() then lastOwnBeacon = GetTime() end -- a guildmate covered this round
			return
		end
		local contact = fromOutside and sender or ns.CanonName(parts[9])
		StoreSheet(name, s, contact)
		if IsRival(g, name) then
			local r = Rivals(g)[name]
			if contact then r.contact = contact end
			-- pass rivals' sheets on to the guild (once in a while)
			if fromOutside and (not r.relayedAt or time() - r.relayedAt > 300) then
				r.relayedAt = time()
				Send("Gbr" .. name, table.concat(parts, ";", 1, 8) .. ";" .. sender)
			end
		end
		ns.MarkChanged()
	elseif kind == "c" then
		local id, from, to = parts[4], parts[5], parts[6]
		if not id or not from or seenIds["c" .. id] then return end
		if from == g.name then
			if not fromOutside then -- our officer's challenge: remember it guild-wide
				g.outgoing = g.outgoing or {}
				g.outgoing[id] = { to = to ~= "" and to or nil, at = time() }
			end
			return
		end
		if channel == "CHANNEL" and to ~= g.name then return end
		if to ~= "" and to ~= nil and to ~= g.name then return end
		seenIds["c" .. id] = true
		if Hidden(g) or IsRival(g, from) or #G.ActiveRivals(g) >= G.MAX_RIVALS then return end
		local contact = fromOutside and sender or ns.CanonName(parts[7])
		pendingIn[id] = { from = from, contact = contact, at = GetTime() }
		if fromOutside then Send("Gcr" .. id, string.format("G;%d;c;%s;%s;%s;%s", ns.PROTO, id, from, g.name, contact or "")) end
		if Officer(g) then
			ShowInvite(g, id, from)
		elseif channel == "WHISPER" then
			local officers = OnlineOfficers(g)
			Whisper("Gn" .. id, string.format("G;%d;n;%s;%s;%s", ns.PROTO, id, g.name, table.concat(officers, ",", 1, math.min(3, #officers))), sender)
		end
	elseif kind == "a" then
		local id, from, to, yes = parts[4], parts[5], parts[6], parts[7] == "yes"
		if from ~= g.name or not to or seenIds["a" .. id] then return end
		local out = g.outgoing and g.outgoing[id]
		if fromOutside and not out then return end -- not a challenge from our guild
		seenIds["a" .. id] = true
		if g.outgoing then g.outgoing[id] = nil end
		if yes then
			MergeRival(g, to, time(), nil, fromOutside and sender or nil)
			if ns.Alerts and ns.Alerts.QueueCard then
				ns.Alerts.QueueCard({ won = true, kicker = L["Guild vs Guild"], title = string.format(L["%s accepted your challenge!"], to), sub = L["Weekly matches start this week."], view = "league" })
			end
			if fromOutside then
				Send("Gar" .. id, table.concat(parts, ";"))
				QueueRivalList(g)
				SendBeacon(g, "WHISPER", sender, "w")
			end
		else
			ns.Print(string.format(L["%s declined your guild's challenge."], to))
		end
		ns.MarkChanged()
	elseif kind == "n" then
		local guild, names = parts[5], parts[6]
		if names and names ~= "" then
			ns.Print(string.format(L["%s can't accept for %s. Try one of their officers: %s"], sender, guild or "?", names:gsub(",", ", ")))
		else
			ns.Print(string.format(L["%s can't accept for %s, and none of their officers are online."], sender, guild or "?"))
		end
	elseif kind == "u" then
		local from, to = parts[4], parts[5]
		local other = (to == g.name and from) or (from == g.name and not fromOutside and to) or nil
		if other and IsRival(g, other) then
			Rivals(g)[other].ended = time()
			if to == g.name then ns.Print(string.format(L["%s ended the guild vs guild rivalry."], from)) end
			ns.MarkChanged()
		end
	elseif kind == "q" then
		local asker = parts[4]
		if channel == "WHISPER" and asker and IsRival(g, asker) and not Hidden(g) then
			local r = Rivals(g)[asker]
			r.contact = sender
			SendBeacon(g, "WHISPER", sender, "q" .. asker)
		end
	elseif kind == "rv" and not fromOutside then
		local changed = false
		for item in (parts[4] or ""):gmatch("[^,]+") do
			local name, since, ended = item:match("^(.-):(%d+):(%d+)$")
			if name and name ~= "" and name ~= g.name then
				if MergeRival(g, name, tonumber(since), tonumber(ended)) then changed = true end
			end
		end
		if changed then ns.MarkChanged() end
	elseif kind == "r" and not fromOutside then
		local week, rival = parts[4], parts[5]
		local r = rival and Rivals(g)[rival]
		if r and week then r.announced = r.announced or {}; r.announced[week] = true end
	end
end
G.Handle = Handle
ns.Comm.leagueHandler = Handle
ns.Comm.handlers.G = function(g, sender, parts) Handle(g, sender, parts, "GUILD") end

---------------------------------------------------------------------------
-- Weekly results, lead changes, the regular broadcast
---------------------------------------------------------------------------
local function RecordResults(g)
	local pw = G.PrevWeek()
	for _, item in ipairs(G.ActiveRivals(g)) do
		local r = item.info
		r.history = r.history or {}
		r.record = r.record or { w = 0, l = 0, d = 0 }
		local done = false
		for _, h in ipairs(r.history) do if h.week == pw then done = true end end
		local theirs = G.TheirSheet(item.name, pw)
		if not done and theirs and (r.since or 0) < (ns.KeyToTime(G.Week()) or time()) then
			local sc = G.Score(G.Sheet(g, pw), theirs)
			if sc and sc.valid then
				local result = (sc.us > sc.them and "w") or (sc.us < sc.them and "l") or "d"
				table.insert(r.history, 1, { week = pw, us = sc.us, them = sc.them, result = result })
				while #r.history > 12 do table.remove(r.history) end
				r.record[result] = (r.record[result] or 0) + 1
				r.lastResult = { week = pw, us = sc.us, them = sc.them, result = result }
				-- one member posts it in guild chat (if the guild posts the MVP)
				r.announced = r.announced or {}
				if g.rules.announceMVP and not r.announced[pw] then
					C_Timer.After(10 + math.random() * 30, function()
						if r.announced[pw] or not (ns.Alerts.CanChat and ns.Alerts.CanChat()) then return end
						r.announced[pw] = true
						Send("Gr" .. pw .. item.name, string.format("G;%d;r;%s;%s;%s", ns.PROTO, pw, item.name, result))
						ns.Alerts.GuildChat(G.ResultLine(g.name, item.name, r.lastResult) .. " (Guild Ranks)")
					end)
				end
			end
		end
	end
end
G.RecordResults = RecordResults

-- Last league week's rival results: "beat Rival 5-3", "lost to Other 3-5" (newest league week only)
function G.LastWeekResults(g)
	local pw, out = G.PrevWeek(), {}
	if not g or g.solo then return out end
	for name, r in pairs(Rivals(g)) do
		local res = r.lastResult
		if res and res.week == pw then out[#out + 1] = { name = name, us = res.us, them = res.them, result = res.result } end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end
function G.ShortResult(item)
	local score = G.FormatPoints(item.us) .. "-" .. G.FormatPoints(item.them)
	if item.result == "w" then return string.format(L["beat %s %s"], item.name, score) end
	if item.result == "l" then return string.format(L["lost to %s %s"], item.name, score) end
	return string.format(L["drew with %s %s"], item.name, score)
end

function G.ResultLine(us, them, res)
	local score = G.FormatPoints(res.us) .. "-" .. G.FormatPoints(res.them)
	if res.result == "w" then return string.format(L["Guild vs Guild: %s beat %s %s last week!"], us, them, score) end
	if res.result == "l" then return string.format(L["Guild vs Guild: %s lost to %s %s last week."], us, them, score) end
	return string.format(L["Guild vs Guild: %s and %s drew %s last week."], us, them, score)
end

local function CheckLeads(g)
	local week = G.Week()
	local mine
	for _, item in ipairs(G.ActiveRivals(g)) do
		local theirs = G.TheirSheet(item.name, week)
		if theirs then
			mine = mine or G.Sheet(g, week)
			local sc = G.Score(mine, theirs)
			local state = (sc and sc.valid) and ((sc.us > sc.them and "lead") or (sc.us < sc.them and "behind") or "tie") or nil
			local r = item.info
			if state and r.leadState and state ~= r.leadState and state ~= "tie" and (not r.leadCardAt or time() - r.leadCardAt > 3600)
				and ns.db.leadCards ~= false and ns.Alerts and ns.Alerts.QueueCard then
				r.leadCardAt = time()
				local score = G.FormatPoints(sc.us) .. " - " .. G.FormatPoints(sc.them)
				ns.Alerts.QueueCard({ won = state == "lead", kicker = L["Guild vs Guild"],
					title = state == "lead" and string.format(L["%s took the lead against %s"], g.name, item.name)
						or string.format(L["%s took the lead against %s"], item.name, g.name),
					sub = score .. "  ·  " .. L["this week"], view = "league" })
			end
			if state then r.leadState = state end
		end
	end
end
G.CheckLeads = CheckLeads

-- Every 30 seconds: one member per guild sends the sheet (channel), asks stale rivals (whisper)
local nextBeacon = 0
function G.Tick()
	local g = ns.G()
	if not g or g.solo or not ns.Comm.CanSend() then return end
	if channelId == 0 and ns.db.leagueChannel ~= false and not G.joinTried then
		G.joinTried = true
		G.JoinChannel()
	end
	local now = GetTime()
	if now >= nextBeacon and now - lastOwnBeacon >= BEACON_EVERY - 60 and not Hidden(g) and ns.db.share then
		nextBeacon = now + BEACON_EVERY + math.random(0, 60)
		lastOwnBeacon = now
		if channelId > 0 then Broadcast(EncodeSheet(g.name, G.Sheet(g)), "Gbc") end
		-- this round's envoy also checks on rivals we haven't heard from
		for _, item in ipairs(G.ActiveRivals(g)) do
			local e = Data().guilds[item.name]
			local fresh = e and e.weeks and e.weeks[G.Week()] and time() - (e.weeks[G.Week()].at or 0) < STALE
			local contact = item.info.contact or (e and e.contacts and e.contacts[1])
			if not fresh and contact and (not lastQuery[item.name] or now - lastQuery[item.name] >= QUERY_EVERY) then
				lastQuery[item.name] = now
				SendBeacon(g, "WHISPER", contact, "s" .. item.name)
				Whisper("Gq" .. item.name, string.format("G;%d;q;%s", ns.PROTO, g.name), contact)
			end
		end
	end
	RecordResults(g)
	CheckLeads(g)
end

function G.Status()
	return { channel = channelId > 0, channelOK = G.ChannelOK(), known = (function()
		local n = 0
		for name, e in pairs(Data().guilds) do if e.weeks and e.weeks[G.Week()] then n = n + 1 end end
		return n
	end)() }
end

ns.OnLogin(function()
	InstallFilter()
	C_Timer.After(15 + math.random() * 30, function()
		G.JoinChannel()
		-- first sheet within ~1.5 min (unless a guildmate already sent one)
		lastOwnBeacon = math.max(lastOwnBeacon, GetTime() - BEACON_EVERY + 30 + math.random(0, 60))
	end)
	C_Timer.NewTicker(30, G.Tick)
end)
