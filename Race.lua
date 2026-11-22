-- Guild Ranks: Race to max level. Who in the guild got there first, how much play time it took,
-- and where everyone else is on the way (with an estimate from their levelling speed this week).
local ADDON, ns = ...
local L = ns.L
local R = {}
ns.Race = R

local function Char() return ns.db and ns.me and ns.db.chars[ns.me] end

-- Our own record lives with the character and is copied onto our entry in the guild
local function SyncOwn()
	local c, g = Char(), ns.G()
	if not c or not g then return end
	local p = ns.GetPlayer(g, ns.me, true)
	p.maxAt, p.maxPlayed, p.maxUnknown = c.maxAt, c.maxPlayed, c.maxUnknown
end

-- Shared with the guild: "M;proto;maxAt;maxPlayed" (0 = unknown; maxAt 0 with level 60 = reached before tracking)
local function QueueMine()
	local c = Char()
	if not c or not ns.db.share then return end
	if not (c.maxAt or c.maxUnknown) then return end
	ns.Comm.Enqueue("M", string.format("M;%d;%d;%d", ns.PROTO, c.maxAt or 0, c.maxPlayed or 0))
end
R.QueueMine = QueueMine
table.insert(ns.Comm.extraSenders, QueueMine)

ns.Comm.handlers.M = function(g, sender, parts)
	local p = ns.GetPlayer(g, sender, true)
	local at, played = tonumber(parts[3]), tonumber(parts[4])
	if not at or not played or at < 0 or played < 0 then return end
	if at > 0 then
		p.maxAt, p.maxUnknown = math.floor(at), nil
	else
		p.maxAt, p.maxUnknown = nil, true
	end
	p.maxPlayed = played > 0 and math.floor(played) or nil
	ns.MarkChanged()
end

-- Players who reached max level, first one first (unknown dates after known ones)
function R.Board(g)
	local maxL = ns.MaxLevel()
	local reached, levelling = {}, {}
	for key, p in pairs(ns.EligiblePlayers(g)) do
		local e = { key = key, name = ns.ShortName(key), class = p.class, level = p.level or 0,
			at = p.maxAt, played = p.maxPlayed, unknown = p.maxUnknown }
		if (p.level or 0) >= maxL or p.maxAt then
			reached[#reached + 1] = e
		elseif (p.level or 0) > 0 then
			-- estimate from this week's levelling speed
			local b = ns.Aggregate(p, "week", g)
			local hours = (b.playtime or 0) / 3600
			local lph = hours >= 0.5 and ((b.mlevels or 0) / 1000) / hours or 0
			e.etaSecs = lph > 0 and ((maxL - e.level) / lph) * 3600 or nil
			e.progress = e.level / maxL
			levelling[#levelling + 1] = e
		end
	end
	table.sort(reached, function(a, b)
		if a.at and b.at then return a.at < b.at end
		if a.at or b.at then return a.at ~= nil end
		return a.name < b.name
	end)
	table.sort(levelling, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		return a.name < b.name
	end)
	return reached, levelling, maxL
end

-- Our place in the race when we got there (1 = first)
local function MyPlace(g)
	local c = Char()
	local place = 1
	for key, p in pairs(g.players) do
		if key ~= ns.me and ((p.level or 0) >= ns.MaxLevel() or p.maxAt) then
			if p.maxUnknown or not p.maxAt or (c.maxAt and p.maxAt < c.maxAt) then place = place + 1 end
		end
	end
	return place
end

local function Ordinal(n)
	local s = "th"
	if n % 100 < 11 or n % 100 > 13 then
		local d = n % 10
		s = (d == 1 and "st") or (d == 2 and "nd") or (d == 3 and "rd") or "th"
	end
	return n .. s
end
R.Ordinal = Ordinal

local waitingForPlayed = false

-- We just reached max level: remember when, ask the game for our total /played
local function Reached()
	local c = Char()
	if not c or c.maxAt then return end
	c.maxAt, c.maxUnknown = time(), nil
	SyncOwn()
	waitingForPlayed = true
	if RequestTimePlayed then RequestTimePlayed() end
	C_Timer.After(10, function() -- if the game never answers, celebrate without the play time
		if waitingForPlayed then waitingForPlayed = false; R.Celebrate() end
	end)
end

function R.Celebrate()
	local c, g = Char(), ns.G()
	if not c or not g or not c.maxAt then return end
	SyncOwn()
	QueueMine()
	local maxL = ns.MaxLevel()
	local place = g.solo and nil or MyPlace(g)
	local played = c.maxPlayed and ns.FormatDuration(c.maxPlayed) or nil
	if ns.Alerts and ns.Alerts.QueueCard then
		local sub = place and string.format(L["%s in %s"], Ordinal(place), g.name) or ""
		if played then sub = sub .. (sub ~= "" and "  ·  " or "") .. string.format(L["%s played"], played) end
		ns.Alerts.QueueCard({ won = true, kicker = string.format(L["Race to %d"], maxL), title = string.format(L["You reached level %d!"], maxL), sub = sub, metric = "race" })
	end
	if place and ns.db.announceMax ~= false and ns.Alerts and ns.Alerts.CanChat and ns.Alerts.CanChat() then
		local msg = string.format(L["%s reached %d! %s in %s"], ns.ShortName(ns.me), maxL, Ordinal(place), g.name)
		if played then msg = msg .. " (" .. string.format(L["%s played"], played) .. ")" end
		ns.Alerts.GuildChat(msg .. " (Guild Ranks)")
	end
	ns.MarkChanged()
end

ns.On("TIME_PLAYED_MSG", function(total)
	if not waitingForPlayed then return end
	waitingForPlayed = false
	local c = Char()
	if c and ns.Readable(total) and type(total) == "number" and total > 0 then c.maxPlayed = math.floor(total) end
	R.Celebrate()
end)

ns.On("PLAYER_LEVEL_UP", function(newLevel)
	if not ns.Readable(newLevel) or type(newLevel) ~= "number" then return end
	if newLevel >= ns.MaxLevel() then C_Timer.After(1, Reached) end
end)

-- Already at max level when the addon first sees this character: the date is unknown
ns.OnGuildChanged(function()
	local c = Char()
	if not c then return end
	if not c.maxAt and not c.maxUnknown and (UnitLevel("player") or 0) >= ns.MaxLevel() then c.maxUnknown = true end
	SyncOwn()
end)
