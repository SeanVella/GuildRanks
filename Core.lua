-- Guild Ranks: core (saved data, per-guild storage, dates, metrics, ranking, helpers)
local ADDON, ns = ...
local L = ns.L
_G.GuildRanks = ns

ns.PREFIX = "GuildRanks"       -- addon message prefix (max 16 chars)
ns.PROTO = 1                   -- wire protocol version
ns.KEEP_DAYS = 62              -- daily history kept per player
do
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
	ns.VERSION = (v and not v:find("@", 1, true)) and v or "dev"
end

---------------------------------------------------------------------------
-- Secret values (Midnight / Forever): numbers hidden from addons in combat
---------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue
function ns.Readable(v)
	if v == nil then return false end
	if issecretvalue and issecretvalue(v) then return false end
	return true
end

function ns.Print(msg)
	print("|cff33ff99" .. L["Guild Ranks"] .. "|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Data definitions
---------------------------------------------------------------------------
-- Fields stored per daily bucket, in wire order. Never reorder; only append.
ns.FIELDS = {
	"playtime", "g_loot", "g_quest", "g_vendor", "g_ah", "g_mail", "g_trade", "g_other",
	"xp", "mlevels", "damage", "healing", "kills", "deaths", "quests", "bosses",
	"dungeons", "gathers", "crafts", "lv_vendor", "lv_auction",
}

ns.GOLD_SOURCES = { "loot", "quest", "vendor", "ah", "mail", "trade", "other" }
ns.GOLD_SOURCE_LABELS = {
	loot = L["Looted"], quest = L["Quest rewards"], vendor = L["Vendor sales"], ah = L["Auction House"],
	mail = L["Mail (not AH)"], trade = L["Trades"], other = L["Other"],
}

ns.METRICS = {
	{ key = "score",    label = L["Guild score (overall)"], short = L["Guild score"], rate = false, fmt = "score" },
	{ key = "gold",     label = L["Gold earned"],       short = L["Gold"],      rate = true, fmt = "money" },
	{ key = "loot",     label = L["Loot value"],        short = L["Loot value"], rate = true, fmt = "money" },
	{ key = "xp",       label = L["Experience"],        short = L["XP"],        rate = true },
	{ key = "levels",   label = L["Levels gained"],     short = L["Levels"],    rate = true, fmt = "levels" },
	{ key = "damage",   label = L["Damage done"],       short = L["Damage"],    rate = true },
	{ key = "healing",  label = L["Healing done"],      short = L["Healing"],   rate = true },
	{ key = "kills",    label = L["Kills (XP-giving)"], short = L["Kills"],     rate = true },
	{ key = "quests",   label = L["Quests completed"],  short = L["Quests"],    rate = true },
	{ key = "bosses",   label = L["Bosses killed"],     short = L["Bosses"],    rate = true },
	{ key = "dungeons", label = L["Dungeon/raid runs"], short = L["Runs"],      rate = true },
	{ key = "gathers",  label = L["Gathering"],         short = L["Gathering"], rate = true },
	{ key = "crafts",   label = L["Items crafted"],     short = L["Crafts"],    rate = true },
	{ key = "deaths",   label = L["Deaths (fewest wins)"], short = L["Deaths"], rate = true, lowerIsBetter = true },
	{ key = "playtime", label = L["Play time"],         short = L["Play time"], rate = false, fmt = "time" },
}
ns.METRIC_BY_KEY = {}
for _, m in ipairs(ns.METRICS) do ns.METRIC_BY_KEY[m.key] = m end

ns.PERIODS = {
	{ key = "today",    label = L["Today"] },
	{ key = "week",     label = L["This week"] },
	{ key = "lastweek", label = L["Last week"] },
	{ key = "month",    label = L["This month"] },
	{ key = "all",      label = L["All time"] },
}
ns.PERIOD_BY_KEY = {}
for _, p in ipairs(ns.PERIODS) do ns.PERIOD_BY_KEY[p.key] = p end

ns.WEEKDAYS = { L["Sunday"], L["Monday"], L["Tuesday"], L["Wednesday"], L["Thursday"], L["Friday"], L["Saturday"] }

-- Default rules for a guild (set by its managers and shared with every member)
function ns.DefaultRules()
	return {
		version = 0,
		resetDay = 4,            -- Wednesday (1 = Sunday ... 7 = Saturday)
		resetHour = 0,           -- hour (realm time) the day and the week start; 5 = 05:00
		minMinutes = 30,         -- minimum play time in the period to be ranked
		gold = { loot = true, quest = true, vendor = true, ah = true, mail = true, trade = true, other = true },
		managerRank = 1,         -- lowest rank index that may change rules (0 = Guild Master)
		showSpoon = true,        -- show the "Wooden spoon" (last place) award
		itemValue = "vendor",    -- loot value: "vendor" (fair for everyone) or "auction" (TSM/Auctionator)
		excluded = {},           -- players hidden from the rankings by managers
		challengeMetric = nil,   -- weekly challenge: featured ranking (per hour)
		challengePrize = nil,    -- weekly challenge: prize text
		goalMetric = nil,        -- guild goal: combined weekly total of this ranking
		goalTarget = 0,          -- guild goal target (copper for gold/loot)
		announceMVP = false,     -- post last week's MVP in guild chat after the reset
		showPlaytime = true,     -- false: play time is hidden for everyone (column, tooltips, ranking)
	}
end

local DEFAULTS = {
	view = { metric = "score", period = "week", perHour = true, bracket = 0, onlineOnly = false },
	ui = { minimap = { hide = false } },
	share = true,                -- share my stats with my guild
	showPlay = true,             -- let guildmates see my play time
	guilds = {},
	chars = {},
}

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end
ns.CopyDefaults = CopyDefaults

function ns.InitDB()
	if type(GuildRanksDB) ~= "table" then GuildRanksDB = {} end
	CopyDefaults(DEFAULTS, GuildRanksDB)
	GuildRanksDB.schema = 2
	ns.db = GuildRanksDB
	-- Data for the removed automatic Discord posting (1.1.0 betas): no longer needed
	ns.db.exportJSON, ns.db.exportAt, ns.db.exportError = nil, nil, nil
	for _, g in pairs(ns.db.guilds) do
		if type(g.rules) ~= "table" then g.rules = {} end
		CopyDefaults(ns.DefaultRules(), g.rules)
		g.players = g.players or {}
		g.hidden = g.hidden or {}
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.frame = CreateFrame("Frame")
local handlers = {}
ns.unsupportedEvents = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		local ok = pcall(ns.frame.RegisterEvent, ns.frame, event)
		if not ok then ns.unsupportedEvents[event] = true end
	end
	table.insert(handlers[event], fn)
end

ns.frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then geterrorhandler()(err) end
	end
end)

local initFns, loginFns, guildFns = {}, {}, {}
ns.addHooks = {}  -- functions(field, amount) called for every tracked change
function ns.OnInit(fn) table.insert(initFns, fn) end
function ns.OnLogin(fn) table.insert(loginFns, fn) end
function ns.OnGuildChanged(fn) table.insert(guildFns, fn) end

function ns.FireGuildChanged()
	for _, fn in ipairs(guildFns) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON or ns.db then return end
	ns.InitDB()
	for _, fn in ipairs(initFns) do fn() end
end)

ns.On("PLAYER_LOGIN", function()
	ns.me = ns.FullName(UnitName("player"))
	ns.db.chars[ns.me] = ns.db.chars[ns.me] or {}
	ns.PruneOldDays()
	for _, fn in ipairs(loginFns) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end)

-- Throttled "data changed" notification (UI refresh)
local changePending = false
function ns.MarkChanged()
	if changePending then return end
	changePending = true
	C_Timer.After(1, function()
		changePending = false
		if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	end)
end

---------------------------------------------------------------------------
-- Names and players
---------------------------------------------------------------------------
function ns.MyRealm()
	return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("[%s%-]", "")
end

function ns.FullName(name)
	if not name or name == "" then return nil end
	if not name:find("-", 1, true) then
		local realm = ns.MyRealm()
		if realm and realm ~= "" then name = name .. "-" .. realm end
	end
	return name
end

-- Same character? Ignores letter case and how the realm is written ("Argent Dawn",
-- "ArgentDawn", "argent-dawn"); a missing realm means your own realm.
local function NameKey(full)
	if type(full) ~= "string" then return nil end
	local name, realm = full:match("^([^%-]+)%-?(.*)$")
	if not name then return nil end
	if realm == "" then realm = ns.MyRealm() or "" end
	return name:lower() .. "-" .. realm:gsub("[%s%-'%.]", ""):lower()
end

function ns.SameCharacter(a, b)
	local ka, kb = NameKey(a), NameKey(b)
	return ka ~= nil and ka == kb
end

-- One of your own characters (this one or an alt that has used Guild Ranks on this account)
function ns.IsMyCharacter(key)
	if not key then return false end
	if ns.me and ns.SameCharacter(key, ns.me) then return true end
	for charKey in pairs((ns.db and ns.db.chars) or {}) do
		if ns.SameCharacter(key, charKey) then return true end
	end
	return false
end

function ns.ShortName(full)
	return (full and full:match("^([^%-]+)")) or full or "?"
end

-- Active guild (the one this character is in) and viewed guild (shown in the window)
function ns.G()
	return ns.gkey and ns.db.guilds[ns.gkey] or nil
end

function ns.V()
	local key = ns.db.view.guild
	if key and ns.db.guilds[key] then return ns.db.guilds[key], key end
	return ns.G(), ns.gkey
end

function ns.NewGuild(name, realm, clubId, solo)
	return { name = name, realm = realm, clubId = clubId, solo = solo or nil,
		rules = ns.DefaultRules(), players = {}, hidden = {} }
end

function ns.GetPlayer(g, key, create)
	if not g or not key then return nil end
	local p = g.players[key]
	if not p and create then
		p = { days = {}, all = {} }
		g.players[key] = p
	end
	if p then
		p.days = p.days or {}
		p.all = p.all or {}
	end
	return p
end

-- Players shown in rankings: not excluded, not hidden, and (for your current
-- guild, once the roster has loaded) still in the guild
function ns.EligiblePlayers(g)
	local list = {}
	-- Only trust the roster for filtering when Blizzard returned all of it
	local useRoster = g == ns.G() and not g.solo and ns.rosterComplete
	for key, p in pairs(g.players) do
		if not g.rules.excluded[key] and not g.hidden[key] and (not useRoster or ns.roster[key]) then
			list[key] = p
		end
	end
	return list
end

function ns.CountPlayers(g)
	local n = 0
	for _ in pairs(ns.EligiblePlayers(g)) do n = n + 1 end
	return n
end

---------------------------------------------------------------------------
-- Dates (realm time, so every guild member uses the same day keys)
---------------------------------------------------------------------------
local cachedToday, cachedWday, cachedAt = nil, nil, -100

-- Days since 1970-01-01 for a calendar date (no time zone involved)
local function DaysFromCivil(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
ns.DaysFromCivil = DaysFromCivil

-- Today's date on the realm. Uses the game calendar; until that has loaded,
-- server time plus the last known realm offset (never the PC's own clock).
-- The guild's reset hour (realm time). A "day" runs from this hour to the same hour
-- the next day, so with 05:00 everything before 05:00 still counts for the day before.
function ns.ResetHour(g)
	g = g or ns.G()
	local h = g and g.rules and tonumber(g.rules.resetHour) or 0
	return math.min(23, math.max(0, math.floor(h)))
end

-- Realm wall-clock time as seconds since 1970 (read as UTC), or nil if unknown yet
function ns.RealmNow()
	local server = GetServerTime and GetServerTime()
	if not server then return nil end
	return server + ((ns.db and ns.db.realmOffset) or 0)
end

function ns.InvalidateToday()
	cachedToday = nil
end
ns.OnGuildChanged(ns.InvalidateToday) -- another guild may use another reset hour

function ns.Today()
	local now = GetTime()
	if not cachedToday or now - cachedAt > 15 then
		local hour = ns.ResetHour()
		local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
		local server = GetServerTime and GetServerTime()
		if t and t.year and t.year > 2000 then
			local days = DaysFromCivil(t.year, t.month, t.monthDay)
			local wday = t.weekday
			if server and ns.db then
				local realmEpoch = days * 86400 + (t.hour or 0) * 3600 + (t.minute or 0) * 60
				ns.db.realmOffset = math.floor((realmEpoch - server) / 900 + 0.5) * 900
			end
			if (t.hour or 0) < hour then -- before the reset hour: still the previous day
				days = days - 1
				wday = (wday + 5) % 7 + 1
			end
			cachedToday = date("!%Y-%m-%d", days * 86400)
			cachedWday = wday
		elseif server then
			local shifted = server + ((ns.db and ns.db.realmOffset) or 0) - hour * 3600
			cachedToday = date("!%Y-%m-%d", shifted)
			cachedWday = tonumber(date("!%w", shifted)) + 1
		else
			local shifted = time() - hour * 3600
			cachedToday = date("%Y-%m-%d", shifted)
			cachedWday = tonumber(date("%w", shifted)) + 1
		end
		cachedAt = now
	end
	return cachedToday, cachedWday
end

function ns.KeyToTime(key)
	local y, m, d = tostring(key):match("^(%d+)-(%d+)-(%d+)$")
	if not y then return nil end
	return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

function ns.ShiftDay(key, days)
	local t = ns.KeyToTime(key)
	return t and date("%Y-%m-%d", t + days * 86400) or key
end

function ns.WeekStart(g)
	local today, wday = ns.Today()
	local back = (wday - ((g and g.rules.resetDay) or 4)) % 7
	return ns.ShiftDay(today, -back)
end

-- Next weekly reset as realm wall-clock seconds (read as UTC), and seconds until then.
-- The active guild's reset hour decides the day keys, so the viewed guild uses it too.
function ns.NextReset(g)
	local y, m, d = ns.WeekStart(g):match("^(%d+)-(%d+)-(%d+)$")
	if not y then return nil end
	local at = (DaysFromCivil(tonumber(y), tonumber(m), tonumber(d)) + 7) * 86400 + ns.ResetHour() * 3600
	local now = ns.RealmNow()
	return at, now and math.max(0, at - now)
end

function ns.FormatCountdown(secs)
	secs = math.max(0, math.floor(secs or 0))
	local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
	if d > 0 then return string.format("%dd %dh", d, h) end
	if h > 0 then return string.format("%dh %dm", h, m) end
	return string.format("%dm", m)
end

-- "Resets Wed 18 Nov, 05:00 realm time · in 2d 9h"
function ns.ResetDescription(g)
	local at, left = ns.NextReset(g)
	if not at then return "" end
	local text = string.format(ns.L["Resets %s, %02d:00 realm time"], date("!%a %d %b", at), ns.ResetHour())
	if left then text = text .. "  ·  " .. string.format(ns.L["in %s"], ns.FormatCountdown(left)) end
	return text
end

-- Play time privacy: hidden for everyone by guild rule, or by the player's own choice
function ns.PlaytimeShownFor(g, key)
	if not g or g.rules.showPlaytime == false then return false end
	if key == ns.me then return true end
	local p = g.players[key]
	return not (p and p.hidePlay)
end

-- Returns a function(dayKey) -> boolean, or nil for "all"
function ns.PeriodFilter(period, g)
	if type(period) == "table" then -- explicit range { from = "YYYY-MM-DD", to = "YYYY-MM-DD" (exclusive) }
		return function(k) return k >= period.from and k < period.to end
	end
	local today = ns.Today()
	if period == "today" then
		return function(k) return k == today end
	elseif period == "week" then
		local start = ns.WeekStart(g)
		return function(k) return k >= start and k <= today end
	elseif period == "lastweek" then
		local thisStart = ns.WeekStart(g)
		local start = ns.ShiftDay(thisStart, -7)
		return function(k) return k >= start and k < thisStart end
	elseif period == "month" then
		local prefix = today:sub(1, 7)
		return function(k) return k:sub(1, 7) == prefix end
	end
	return nil
end

function ns.PeriodDescription(period, g)
	if type(period) == "table" then
		local a, b = ns.KeyToTime(period.from), ns.KeyToTime(period.to)
		return (a and b) and (date("%a %d %b", a) .. " - " .. date("%a %d %b", b - 86400)) or ""
	end
	if period == "week" then
		local t = ns.KeyToTime(ns.WeekStart(g))
		local hour = ns.ResetHour()
		return t and (L["since"] .. " " .. date("%a %d %b", t) .. (hour > 0 and string.format(" %02d:00", hour) or "")) or ""
	elseif period == "lastweek" then
		local t = ns.KeyToTime(ns.WeekStart(g))
		return t and (date("%a %d %b", t - 7 * 86400) .. " - " .. date("%a %d %b", t - 86400)) or ""
	elseif period == "today" then
		local t = ns.KeyToTime(ns.Today())
		return t and date("%a %d %b", t) or ""
	elseif period == "month" then
		local t = ns.KeyToTime(ns.Today())
		return t and date("%B %Y", t) or ""
	end
	return L["everything recorded"]
end

function ns.PruneOldDays()
	local cutoff = ns.ShiftDay(ns.Today(), -ns.KEEP_DAYS)
	for _, g in pairs(ns.db.guilds) do
		for _, p in pairs(g.players) do
			for day in pairs(p.days or {}) do
				if day < cutoff then p.days[day] = nil end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Aggregation and ranking
---------------------------------------------------------------------------
function ns.Aggregate(p, period, g)
	if period == "all" then return p.all or {} end
	local filter = ns.PeriodFilter(period, g)
	local sum = {}
	for day, b in pairs(p.days or {}) do
		if filter(day) then
			for k, v in pairs(b) do
				if type(v) == "number" then sum[k] = (sum[k] or 0) + v end
			end
		end
	end
	return sum
end

function ns.MetricTotal(b, key, g)
	if key == "gold" then
		local total, enabled = 0, g.rules.gold
		for _, src in ipairs(ns.GOLD_SOURCES) do
			if enabled[src] then total = total + (b["g_" .. src] or 0) end
		end
		return total
	elseif key == "loot" then
		return (g.rules.itemValue == "auction") and (b.lv_auction or 0) or (b.lv_vendor or 0)
	elseif key == "levels" then
		return (b.mlevels or 0) / 1000
	end
	return b[key] or 0
end

function ns.MaxLevel()
	local m = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
		or (GetMaxPlayerLevel and GetMaxPlayerLevel())
	if type(m) ~= "number" or m < 2 then m = 60 end
	return m
end

function ns.Brackets()
	local maxL = ns.MaxLevel()
	local list = { { value = 0, text = L["All levels"] } }
	local lo, hi, i = 1, 19, 1
	while lo < maxL do
		local top = math.min(hi, maxL - 1)
		list[#list + 1] = { value = i, text = lo .. "-" .. top, min = lo, max = top }
		i = i + 1
		lo = top + 1
		hi = lo + 9
	end
	list[#list + 1] = { value = i, text = tostring(maxL), min = maxL, max = maxL }
	return list
end

local function FindBracket(bracket)
	if not bracket or bracket <= 0 then return nil end
	for _, b in ipairs(ns.Brackets()) do
		if b.value == bracket then return b end
	end
	return nil
end

local function InBracket(br, lvl)
	return not br or (lvl >= br.min and lvl <= br.max)
end

---------------------------------------------------------------------------
-- Guild score: overall 0-100 score from placement in 8 equally weighted
-- categories. Only players with the minimum play time take part.
---------------------------------------------------------------------------
ns.SCORE_CATEGORIES = {
	{ key = "gold",   label = L["gold"] },
	{ key = "levels", label = L["levels"] },
	{ key = "combat", label = L["combat"], combat = true },
	{ key = "quests", label = L["quests"] },
	{ key = "kills",  label = L["kills"] },
	{ key = "runs",   label = L["bosses and runs"] },
	{ key = "craft",  label = L["gathering and crafting"] },
	{ key = "deaths", label = L["fewest deaths"], lower = true },
}

local function CategoryValue(cat, b, g)
	if cat == "gold" then return ns.MetricTotal(b, "gold", g) end
	if cat == "levels" then return ns.MetricTotal(b, "levels", g) end
	if cat == "runs" then return (b.bosses or 0) + (b.dungeons or 0) end
	if cat == "craft" then return (b.gathers or 0) + (b.crafts or 0) end
	return b[cat] or 0
end

-- Higher-is-better: players with 0 get 0; the rest share (0, 100] by placement.
-- Lower-is-better: everyone placed from 100 (best) to 0 (worst). Ties share the average place.
local function PlacementScores(entries, getValue, lower)
	local scores, list = {}, {}
	for _, e in ipairs(entries) do
		local v = getValue(e)
		if lower or v > 0 then
			list[#list + 1] = { e = e, v = v }
		else
			scores[e] = 0
		end
	end
	table.sort(list, function(a, b)
		if lower then return a.v < b.v end
		return a.v > b.v
	end)
	local n, i = #list, 1
	while i <= n do
		local j = i
		while j < n and list[j + 1].v == list[i].v do j = j + 1 end
		local pos = (i + j) / 2 - 1
		local s
		if lower then
			s = (n <= 1) and 100 or 100 * (n - 1 - pos) / (n - 1)
		else
			s = 100 * (n - pos) / n
		end
		for k = i, j do scores[list[k].e] = s end
		i = j + 1
	end
	return scores
end

function ns.ComputeScores(g, period, bracket)
	local minSecs = math.max(60, (g.rules.minMinutes or 0) * 60)
	local br = FindBracket(bracket)
	local entries = {}
	for key, p in pairs(ns.EligiblePlayers(g)) do
		local lvl = p.level or 0
		if InBracket(br, lvl) then
			local b = ns.Aggregate(p, period, g)
			local secs = b.playtime or 0
			if secs >= minSecs then
				entries[#entries + 1] = {
					key = key, name = ns.ShortName(key), class = p.class, level = lvl, version = p.version,
					bucket = b, playtime = secs, hours = secs / 3600, cats = {},
				}
			end
		end
	end
	if #entries == 0 then return entries end

	for _, cat in ipairs(ns.SCORE_CATEGORIES) do
		if cat.combat then
			local sd = PlacementScores(entries, function(e) return (e.bucket.damage or 0) / e.hours end)
			local sh = PlacementScores(entries, function(e) return (e.bucket.healing or 0) / e.hours end)
			for _, e in ipairs(entries) do e.cats.combat = math.max(sd[e], sh[e]) end
		else
			local s = PlacementScores(entries, function(e) return CategoryValue(cat.key, e.bucket, g) / e.hours end, cat.lower)
			for _, e in ipairs(entries) do e.cats[cat.key] = s[e] end
		end
	end
	for _, e in ipairs(entries) do
		local sum = 0
		for _, cat in ipairs(ns.SCORE_CATEGORIES) do sum = sum + e.cats[cat.key] end
		e.score = math.floor(sum / #ns.SCORE_CATEGORIES + 0.5)
		e.value, e.total = e.score, e.score
	end
	table.sort(entries, function(a, b)
		if a.score == b.score then return a.name < b.name end
		return a.score > b.score
	end)
	return entries
end

-- Last week's MVP and Wooden spoon. Spoon is nil if the guild turned it off.
function ns.WeeklyAwards(g)
	local list = ns.ComputeScores(g, "lastweek", 0)
	if #list < 2 then return nil end
	return list[1], g.rules.showSpoon and list[#list] or nil, #list
end

-- Returns rows (sorted), number of unranked players, metric, useRate
function ns.BuildBoard(g, metricKey, period, perHour, bracket)
	local metric = ns.METRIC_BY_KEY[metricKey] or ns.METRICS[1]
	local useRate = metric.rate and perHour and true or false
	local minSecs = (g.rules.minMinutes or 0) * 60
	local br = FindBracket(bracket)
	local eligible = ns.EligiblePlayers(g)

	if metric.key == "score" then
		local rows = ns.ComputeScores(g, period, bracket)
		local unranked = 0
		for _, p in pairs(eligible) do
			if InBracket(br, p.level or 0) then
				local secs = ns.Aggregate(p, period, g).playtime or 0
				if secs > 0 and secs < math.max(60, minSecs) then unranked = unranked + 1 end
			end
		end
		return rows, unranked, metric, false
	end

	local rows, unranked = {}, 0
	local isPlaytime = metric.key == "playtime"
	if isPlaytime and g.rules.showPlaytime == false then return rows, 0, metric, false end
	for key, p in pairs(eligible) do
		local lvl = p.level or 0
		if InBracket(br, lvl) and not (isPlaytime and not ns.PlaytimeShownFor(g, key)) then
			local b = ns.Aggregate(p, period, g)
			local secs = b.playtime or 0
			if secs > 0 then
				local total = ns.MetricTotal(b, metric.key, g)
				if (useRate or metric.lowerIsBetter) and secs < minSecs then
					unranked = unranked + 1
				elseif total > 0 or metric.lowerIsBetter then
					rows[#rows + 1] = {
						key = key, name = ns.ShortName(key), class = p.class, level = lvl,
						version = p.version, seen = p.seen,
						value = useRate and (total / (secs / 3600)) or total,
						total = total, playtime = secs, bucket = b,
					}
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.value == b.value then return a.name < b.name end
		if metric.lowerIsBetter then return a.value < b.value end
		return a.value > b.value
	end)
	return rows, unranked, metric, useRate
end

---------------------------------------------------------------------------
-- Weekly challenge and guild goal
---------------------------------------------------------------------------
-- The period to compare with for rank changes ("vs last week"), or nil
function ns.PreviousPeriod(period, g)
	local today = ns.Today()
	if period == "today" then
		return { from = ns.ShiftDay(today, -1), to = today }
	elseif period == "week" then
		return "lastweek"
	elseif period == "lastweek" then
		local start = ns.WeekStart(g)
		return { from = ns.ShiftDay(start, -14), to = ns.ShiftDay(start, -7) }
	elseif period == "month" then
		local y, m = today:match("^(%d+)-(%d+)")
		y, m = tonumber(y), tonumber(m)
		local py, pm = (m == 1) and (y - 1) or y, (m == 1) and 12 or (m - 1)
		return { from = string.format("%04d-%02d-01", py, pm), to = string.format("%04d-%02d-01", y, m) }
	end
	return nil
end

-- Rank changes against the previous period: key -> number of places moved up
-- (negative = down, 0 = same), or "new" for players not ranked last time.
-- Empty when there's nothing to compare with.
function ns.RankChanges(g, rows, metricKey, period, perHour, bracket)
	local prevPeriod = ns.PreviousPeriod(period, g)
	if not prevPeriod then return {} end
	local prev = ns.BuildBoard(g, metricKey, prevPeriod, perHour, bracket)
	if #prev == 0 then return {} end
	local before = {}
	for i, r in ipairs(prev) do before[r.key] = i end
	local out = {}
	for i, r in ipairs(rows) do
		out[r.key] = before[r.key] and (before[r.key] - i) or "new"
	end
	return out
end

-- Ready-made invite message for guild chat or Discord (kept under 255 characters)
function ns.InviteMessage()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local site = get and get("GuildRanks", "X-Website")
	if type(site) ~= "string" or site == "" then site = "https://github.com/SeanVella/GuildRanks" end
	site = site:gsub("^https?://", "") .. "/releases"
	return string.format(ns.L["Join our guild competition! Install Guild Ranks: CurseForge app, search \"Guild Ranks\" (Forever), or %s"], site)
end

-- Rankings to choose from in the window (Play time is left out when the guild hides it)
function ns.RankingChoices(g)
	local o = {}
	for _, m in ipairs(ns.METRICS) do
		if m.key ~= "playtime" or not g or g.rules.showPlaytime ~= false then o[#o + 1] = { value = m.key, text = m.label } end
	end
	return o
end

-- Rankings that make sense as a challenge (per hour) or goal (combined total)
function ns.ChallengeChoices()
	local o = { { value = "", text = ns.L["No challenge"] } }
	for _, m in ipairs(ns.METRICS) do
		if m.rate and not m.lowerIsBetter then o[#o + 1] = { value = m.key, text = m.label } end
	end
	return o
end

function ns.GoalChoices()
	local o = { { value = "", text = ns.L["No goal"] } }
	for _, m in ipairs(ns.METRICS) do
		if m.rate and not m.lowerIsBetter and m.key ~= "levels" then o[#o + 1] = { value = m.key, text = m.label } end
	end
	return o
end

-- Leader of the weekly challenge for a period: row, metric (or nil)
function ns.ChallengeLeader(g, period)
	local key = g.rules.challengeMetric
	if not key or not ns.METRIC_BY_KEY[key] then return nil end
	local rows, _, metric = ns.BuildBoard(g, key, period or "week", true, 0)
	return rows[1], metric
end

-- Guild goal progress this week: current, target, metric (or nil)
function ns.GoalProgress(g, period)
	local key, target = g.rules.goalMetric, g.rules.goalTarget or 0
	if not key or not ns.METRIC_BY_KEY[key] or target <= 0 then return nil end
	local total = 0
	for _, p in pairs(ns.EligiblePlayers(g)) do
		total = total + ns.MetricTotal(ns.Aggregate(p, period or "week", g), key, g)
	end
	return total, target, ns.METRIC_BY_KEY[key]
end

-- Remove characters that would break chat or addon messages
function ns.CleanText(s, maxLen)
	s = tostring(s or ""):gsub("[;|,\n\r]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
	return s
end

---------------------------------------------------------------------------
-- Formatting (plain = no colour codes, for Discord)
---------------------------------------------------------------------------
function ns.FormatInt(n)
	local s = string.format("%.0f", n or 0)
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^(-?),", "%1"))
end

function ns.FormatNumber(n)
	n = n or 0
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e4 then return string.format("%.1fK", n / 1e3) end
	if n < 10 and n ~= math.floor(n) then return string.format("%.2f", n) end
	return ns.FormatInt(n)
end

function ns.FormatMoney(copper, plain)
	copper = math.floor((copper or 0) + 0.5)
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if plain then
		if g > 0 then return string.format("%sg %ds", ns.FormatInt(g), s) end
		if s > 0 then return string.format("%ds %dc", s, c) end
		return string.format("%dc", c)
	end
	if g > 0 then return string.format("%s|cffffd700g|r %d|cffc7c7cfs|r", ns.FormatInt(g), s) end
	if s > 0 then return string.format("%d|cffc7c7cfs|r %d|cffeda55fc|r", s, c) end
	return string.format("%d|cffeda55fc|r", c)
end

function ns.FormatTime(secs)
	secs = math.floor(secs or 0)
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	if h > 0 then return string.format("%dh %02dm", h, m) end
	return string.format("%dm", m)
end

-- "just now", "2 min ago", "3 h ago", "2 days ago"
function ns.FormatAgo(t)
	if not t then return ns.L["never"] end
	local secs = math.max(0, time() - t)
	if secs < 60 then return ns.L["just now"] end
	if secs < 3600 then return string.format(ns.L["%d min ago"], math.floor(secs / 60)) end
	if secs < 86400 then return string.format(ns.L["%d h ago"], math.floor(secs / 3600)) end
	return string.format(ns.L["%d days ago"], math.floor(secs / 86400))
end

function ns.FormatValue(metric, v, isRate, plain)
	local s
	if metric.fmt == "money" then
		s = ns.FormatMoney(v, plain)
	elseif metric.fmt == "levels" then
		s = string.format("%.2f", v or 0)
	elseif metric.fmt == "time" then
		s = ns.FormatTime(v)
	elseif metric.fmt == "score" then
		s = string.format("%d", math.floor((v or 0) + 0.5))
	elseif isRate then
		s = (v or 0) < 100 and string.format("%.1f", v or 0) or ns.FormatNumber(v)
	else
		s = ns.FormatNumber(v)
	end
	if isRate then s = s .. "/h" end
	return s
end
