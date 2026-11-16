-- Guild Ranks: personal features — personal bests, goals, weekly titles, rival and
-- session recap. Stored per character (ns.db.chars[me].personal), so alts stay separate.
local ADDON, ns = ...
local L = ns.L
local P = {}
ns.Personal = P

local function Data()
	if not ns.db or not ns.me then return nil end
	local c = ns.db.chars[ns.me]
	if not c then return nil end
	c.personal = c.personal or {}
	local d = c.personal
	d.records = d.records or {}
	d.goals = d.goals or {}
	d.rivalState = d.rivalState or {}
	return d
end
P.Data = Data

-- My own player record in the active guild (or solo)
local function Me()
	local g = ns.G()
	return g, g and g.players[ns.me]
end

-- Personal values: gold counts every source (your own goals and bests aren't bound by guild rules)
function P.Value(b, key)
	if not b then return 0 end
	if key == "gold" then
		local t = 0
		for _, src in ipairs(ns.GOLD_SOURCES) do t = t + (b["g_" .. src] or 0) end
		return t
	elseif key == "levels" then
		return (b.mlevels or 0) / 1000
	end
	return b[key] or 0
end

function P.Bucket(period)
	local g, p = Me()
	if not p then return {} end
	return ns.Aggregate(p, period, g)
end

---------------------------------------------------------------------------
-- Personal bests (per day), with a toast when one is beaten
---------------------------------------------------------------------------
P.RECORDS = {
	{ key = "goldph", label = L["Gold/h in a day"], fmt = "money" },
	{ key = "gold",   label = L["Gold in a day"],   fmt = "money" },
	{ key = "xp",     label = L["XP in a day"] },
	{ key = "levels", label = L["Levels in a day"], fmt = "levels" },
	{ key = "quests", label = L["Quests in a day"] },
	{ key = "kills",  label = L["Kills in a day"] },
	{ key = "streak", label = L["Days in a row"] },
}
local MIN_RATE_SECS = 1800 -- gold per hour only counts days with 30+ minutes played

local function DayValue(rec, b)
	if rec.key == "goldph" then
		local secs = b.playtime or 0
		if secs < MIN_RATE_SECS then return nil end
		return P.Value(b, "gold") / (secs / 3600)
	end
	local v = P.Value(b, rec.key)
	return v > 0 and v or nil
end

function P.FormatRecord(rec, v)
	if rec.fmt == "money" then return ns.FormatMoney(v) end
	if rec.fmt == "levels" then return string.format("%.2f", v) end
	if rec.key == "streak" then return tostring(v) end
	return ns.FormatNumber(math.floor(v + 0.5))
end

-- Days in a row with play time, ending today (or yesterday if you haven't played yet today)
function P.Streak()
	local g, p = Me()
	if not p then return 0 end
	local day = ns.Today()
	if not (p.days[day] and (p.days[day].playtime or 0) >= 60) then day = ns.ShiftDay(day, -1) end
	local n = 0
	while p.days[day] and (p.days[day].playtime or 0) >= 60 and n < 400 do
		n = n + 1
		day = ns.ShiftDay(day, -1)
	end
	return n
end

-- Fill records from the days we still have (silently, e.g. on first use)
function P.SeedRecords()
	local d = Data()
	local g, p = Me()
	if not d or not p then return end
	for _, rec in ipairs(P.RECORDS) do
		if rec.key ~= "streak" then
			for day, b in pairs(p.days) do
				local v = DayValue(rec, b)
				local r = d.records[rec.key]
				if v and (not r or v > r.value) then d.records[rec.key] = { value = v, day = day } end
			end
		end
	end
	local s = P.Streak()
	local r = d.records.streak
	if s > 0 and (not r or s > r.value) then d.records.streak = { value = s, day = ns.Today() } end
end

local session -- defined below

function P.CheckRecords()
	local d = Data()
	local g, p = Me()
	if not d or not p then return end
	local today = ns.Today()
	local b = p.days[today] or {}
	for _, rec in ipairs(P.RECORDS) do
		local v
		if rec.key == "streak" then v = P.Streak() else v = DayValue(rec, b) end
		local r = d.records[rec.key]
		if v and v > 0 then
			if not r then
				d.records[rec.key] = { value = v, day = today } -- first one: no fanfare
			elseif v > r.value then
				local beaten = r.day ~= today and r.value > 0 and (rec.key ~= "streak" or r.value >= 2)
				if beaten and d.toasted ~= rec.key .. today then
					d.toasted = rec.key .. today
					ns.Alerts.Toast(string.format(L["New personal best! %s: %s (was %s)"], rec.label,
						P.FormatRecord(rec, v), P.FormatRecord(rec, r.value)))
					session.bests[rec.label] = true
				end
				r.value, r.day = v, today
			end
		end
	end
end

---------------------------------------------------------------------------
-- Personal goals (up to 3): an amount this week/month, or reach a level
---------------------------------------------------------------------------
P.GOAL_TYPES = {
	{ value = "gold",    text = L["Gold"] },
	{ value = "xp",      text = L["Experience"] },
	{ value = "levels",  text = L["Levels gained"] },
	{ value = "quests",  text = L["Quests"] },
	{ value = "kills",   text = L["Kills"] },
	{ value = "gathers", text = L["Gathering"] },
	{ value = "crafts",  text = L["Items crafted"] },
	{ value = "level",   text = L["Reach level"] },
}
P.MAX_GOALS = 3

local function CurrentLevel()
	local lvl = UnitLevel("player") or 1
	local xp, max = UnitXP("player"), UnitXPMax("player")
	if ns.Readable(xp) and ns.Readable(max) and max and max > 0 then return lvl + xp / max end
	return lvl
end

function P.AddGoal(kind, target, period)
	local d = Data()
	if not d or #d.goals >= P.MAX_GOALS then return false end
	target = tonumber(target)
	if not target or target <= 0 then return false end
	local goal = { kind = kind, target = target, period = (kind == "level") and nil or (period == "month" and "month" or "week") }
	if kind == "level" then
		goal.start = CurrentLevel()
		if target <= goal.start then return false end
	end
	d.goals[#d.goals + 1] = goal
	ns.MarkChanged()
	return true
end

function P.RemoveGoal(i)
	local d = Data()
	if d and d.goals[i] then table.remove(d.goals, i); ns.MarkChanged() end
end

local function TypeText(kind)
	for _, t in ipairs(P.GOAL_TYPES) do if t.value == kind then return t.text end end
	return kind
end

function P.GoalLabel(goal)
	if goal.kind == "level" then return string.format(L["Reach level %d"], goal.target) end
	local amount = goal.kind == "gold" and ns.FormatMoney(goal.target * 10000) or ns.FormatNumber(goal.target)
	local name = goal.kind == "gold" and "" or (" " .. TypeText(goal.kind):lower())
	return string.format(goal.period == "month" and L["%s%s this month"] or L["%s%s this week"], amount, name)
end

-- Share of the period that has gone by (0..1)
local function Elapsed(period)
	if period == "month" then
		local today = ns.Today()
		local y, m, dd = today:match("^(%d+)-(%d+)-(%d+)$")
		y, m, dd = tonumber(y), tonumber(m), tonumber(dd)
		local days = ns.DaysFromCivil(m == 12 and y + 1 or y, m == 12 and 1 or m + 1, 1) - ns.DaysFromCivil(y, m, 1)
		return math.min(1, (dd - 0.5) / days)
	end
	local _, left = ns.NextReset(ns.G())
	if not left then return 0.5 end
	return math.max(0, math.min(1, 1 - left / (7 * 86400)))
end

-- Progress: current, fraction (0..1), status text, done?
function P.GoalProgress(goal)
	if goal.kind == "level" then
		local cur = CurrentLevel()
		local span = goal.target - (goal.start or cur)
		local frac = span > 0 and math.max(0, math.min(1, (cur - (goal.start or cur)) / span)) or 1
		if cur >= goal.target then return cur, 1, L["Done!"], true end
		local b = P.Bucket("week")
		local hours = (b.playtime or 0) / 3600
		local lph = hours > 0.25 and P.Value(b, "levels") / hours or 0
		local status = lph > 0 and string.format(L["about %s at your pace"], ns.FormatTime((goal.target - cur) / lph * 3600))
			or L["play a little to see your pace"]
		return cur, frac, string.format("%.1f  ·  ", cur) .. status, false
	end
	local cur = P.Value(P.Bucket(goal.period), goal.kind)
	local target = goal.kind == "gold" and goal.target * 10000 or goal.target
	local frac = math.min(1, cur / target)
	local shown = goal.kind == "gold" and ns.FormatMoney(cur) or ns.FormatNumber(math.floor(cur + 0.5))
	if cur >= target then return cur, 1, shown .. "  ·  " .. L["Done!"], true end
	local expected = Elapsed(goal.period)
	if frac >= expected * 0.95 then return cur, frac, shown .. "  ·  |cff40ff40" .. L["on track"] .. "|r", false end
	local behind = expected * target - cur
	local behindText = goal.kind == "gold" and ns.FormatMoney(behind) or ns.FormatNumber(math.ceil(behind))
	return cur, frac, shown .. "  ·  |cffffaa40" .. string.format(L["%s behind"], behindText) .. "|r", false
end

local function PeriodId(goal)
	if goal.kind == "level" then return "level" end
	if goal.period == "month" then return ns.Today():sub(1, 7) end
	return ns.WeekStart(ns.G())
end

function P.CheckGoals()
	local d = Data()
	if not d or not ns.G() then return end
	for _, goal in ipairs(d.goals) do
		local id = PeriodId(goal)
		if goal.doneFor ~= id then
			local _, _, _, done = P.GoalProgress(goal)
			if done then
				goal.doneFor = id
				ns.Alerts.Toast(string.format(L["Goal reached: %s!"], P.GoalLabel(goal)))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Weekly titles: #1 last week in a ranking (held for the current week)
---------------------------------------------------------------------------
P.TITLES = {
	{ code = "mvp",      metric = "score",    name = L["MVP"] },
	{ code = "gold",     metric = "gold",     name = L["Gold Baron"] },
	{ code = "loot",     metric = "loot",     name = L["Treasure Hunter"] },
	{ code = "xp",       metric = "xp",       name = L["Fast Learner"] },
	{ code = "levels",   metric = "levels",   name = L["Rising Star"] },
	{ code = "damage",   metric = "damage",   name = L["Heavy Hitter"] },
	{ code = "healing",  metric = "healing",  name = L["Life Saver"] },
	{ code = "kills",    metric = "kills",    name = L["Slayer"] },
	{ code = "quests",   metric = "quests",   name = L["Quest Machine"] },
	{ code = "bosses",   metric = "bosses",   name = L["Boss Hunter"] },
	{ code = "dungeons", metric = "dungeons", name = L["Dungeon Crawler"] },
	{ code = "gathers",  metric = "gathers",  name = L["Gatherer"] },
	{ code = "crafts",   metric = "crafts",   name = L["Artisan"] },
	{ code = "deaths",   metric = "deaths",   name = L["Iron Man"] },
}
P.TITLE_BY_CODE = {}
for _, t in ipairs(P.TITLES) do P.TITLE_BY_CODE[t.code] = t end

local titleCache = {}

-- code -> { key = true } for everyone holding that title this week
function P.TitleHolders(g)
	if not g then return {} end
	local week = ns.WeekStart(g)
	local c = titleCache[g]
	if c and c.week == week and GetTime() - c.at < 120 then return c.holders end
	local holders = {}
	for _, t in ipairs(P.TITLES) do
		local set = {}
		if t.code == "mvp" then
			local mvp = ns.WeeklyAwards(g)
			if mvp then set[mvp.key] = true end
		else
			local rows = ns.BuildBoard(g, t.metric, "lastweek", true, 0)
			if #rows >= 2 then
				local top = rows[1].value
				local valid = (t.code == "deaths") and top == 0 or (t.code ~= "deaths" and top > 0)
				if valid then
					for _, r in ipairs(rows) do if r.value == top then set[r.key] = true end end
				end
			end
		end
		holders[t.code] = set
	end
	titleCache[g] = { week = week, at = GetTime(), holders = holders }
	return holders
end

function P.ClearTitleCache() titleCache = {} end

-- List of title entries a player holds this week
function P.TitlesFor(g, key)
	local out, holders = {}, P.TitleHolders(g)
	for _, t in ipairs(P.TITLES) do
		if holders[t.code] and holders[t.code][key] then out[#out + 1] = t end
	end
	return out
end

-- The title a player chose to show (only if they really hold it this week)
function P.ShownTitle(g, key)
	if not g then return nil end
	local code
	if key == ns.me then
		local d = Data()
		code = d and d.title
	else
		local p = g.players[key]
		code = p and p.title
	end
	if not code then return nil end
	local holders = P.TitleHolders(g)
	if holders[code] and holders[code][key] then return P.TITLE_BY_CODE[code] end
	return nil
end

function P.SetTitle(code)
	local d = Data()
	if not d then return end
	d.title = (code and P.TITLE_BY_CODE[code]) and code or nil
	if ns.Comm then ns.Comm.QueueAll() end
	ns.MarkChanged()
end

function P.MyTitleCode()
	local d = Data()
	return d and d.title
end

---------------------------------------------------------------------------
-- Rival: head to head with a guildmate you pick
---------------------------------------------------------------------------
P.RIVAL_METRICS = {
	{ key = "score",  label = L["Guild score"], perHour = false },
	{ key = "gold",   label = L["Gold/h"],      perHour = true },
	{ key = "xp",     label = L["XP/h"],        perHour = true },
	{ key = "quests", label = L["Quests"],      perHour = false },
	{ key = "kills",  label = L["Kills"],       perHour = false },
}

function P.Rival()
	local d = Data()
	return d and d.rival
end

function P.SetRival(key)
	local d = Data()
	if not d then return end
	d.rival = (key ~= ns.me) and key or nil
	d.rivalState = {}
	ns.MarkChanged()
end

-- Rows { label, mine, theirs, metric } for a period (values nil when not ranked)
function P.HeadToHead(g, period)
	local rival = P.Rival()
	if not g or not rival then return {} end
	local out = {}
	for _, m in ipairs(P.RIVAL_METRICS) do
		local rows = ns.BuildBoard(g, m.key, period, m.perHour, 0)
		local mine, theirs
		for _, r in ipairs(rows) do
			if r.key == ns.me then mine = r.value end
			if r.key == rival then theirs = r.value end
		end
		out[#out + 1] = { label = m.label, mine = mine, theirs = theirs, metric = ns.METRIC_BY_KEY[m.key], perHour = m.perHour, key = m.key }
	end
	return out
end

function P.CheckRival()
	local d = Data()
	local g = ns.G()
	local rival = P.Rival()
	if not d or not g or not rival or g.solo then return end
	local name = ns.ShortName(rival)
	for _, row in ipairs(P.HeadToHead(g, "week")) do
		if row.key ~= "quests" and row.key ~= "kills" and row.mine and row.theirs and row.mine ~= row.theirs then
			local state = row.mine > row.theirs and "ahead" or "behind"
			local before = d.rivalState[row.key]
			if before and before ~= state then
				if state == "ahead" then
					ns.Alerts.Toast(string.format(L["You passed your rival %s in %s!"], name, row.label))
				else
					ns.Alerts.Toast(string.format(L["Your rival %s passed you in %s."], name, row.label))
				end
			end
			d.rivalState[row.key] = state
		end
	end
end

---------------------------------------------------------------------------
-- Session recap
---------------------------------------------------------------------------
session = { start = nil, totals = {}, bests = {} }
P.session = session

table.insert(ns.addHooks, function(field, amount)
	session.totals[field] = (session.totals[field] or 0) + amount
end)

local function Snapshot()
	local copyT, copyB = {}, {}
	for k, v in pairs(session.totals) do copyT[k] = v end
	for k in pairs(session.bests) do copyB[#copyB + 1] = k end
	return { start = session.start, finish = time(), totals = copyT, bests = copyB }
end

function P.CurrentSession() return Snapshot() end

function P.LastSession()
	local d = Data()
	return d and d.lastSession
end

-- Lines for the recap window, plus a one-line version for guild chat
function P.SessionLines(s)
	local t = s.totals or {}
	local gold = P.Value(t, "gold")
	local lines = {}
	lines[#lines + 1] = string.format("%s  ·  +%s  ·  %s %s", ns.FormatTime(t.playtime or 0), ns.FormatMoney(gold),
		string.format("%.1f", (t.mlevels or 0) / 1000), L["levels"])
	lines[#lines + 1] = string.format(L["%d quests  ·  %d kills  ·  %d deaths"], t.quests or 0, t.kills or 0, t.deaths or 0)
	if (t.gathers or 0) > 0 or (t.crafts or 0) > 0 then
		lines[#lines + 1] = string.format(L["%d gathered  ·  %d crafted"], t.gathers or 0, t.crafts or 0)
	end
	for _, b in ipairs(s.bests or {}) do lines[#lines + 1] = "|cff40ff40" .. L["New best"] .. ": " .. b .. "|r" end
	local chat = string.format(L["My session: %s, +%s, %.1f levels, %d quests, %d kills (Guild Ranks)"],
		ns.FormatTime(t.playtime or 0), ns.FormatMoney(gold, true), (t.mlevels or 0) / 1000, t.quests or 0, t.kills or 0)
	return lines, chat
end

ns.On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
	local d = Data()
	if not d then return end
	local pending = d.pendingSession
	d.pendingSession = nil
	if isReloadingUi and pending and time() - (pending.finish or 0) < 600 then
		-- a /reload: carry on with the same session
		session.start = pending.start or time()
		for k, v in pairs(pending.totals or {}) do session.totals[k] = (session.totals[k] or 0) + v end
		for _, b in ipairs(pending.bests or {}) do session.bests[b] = true end
		return
	end
	session.start = session.start or time()
	if pending and ((pending.totals or {}).playtime or 0) >= 300 then
		d.lastSession = pending
		C_Timer.After(10, function() if ns.ShowRecap then ns.ShowRecap(pending, true) end end)
	end
end)

ns.On("PLAYER_LOGOUT", function()
	local d = Data()
	if d and session.start then d.pendingSession = Snapshot() end
end)

---------------------------------------------------------------------------
-- Background checks
---------------------------------------------------------------------------
function P.CheckAll()
	if not ns.G() then return end
	pcall(P.CheckRecords)
	pcall(P.CheckGoals)
	pcall(P.CheckRival)
end

ns.OnGuildChanged(function()
	P.ClearTitleCache()
	P.SeedRecords()
	-- remember the rival's current position without alerting
	C_Timer.After(15, function() pcall(P.CheckRival) end)
end)

ns.OnLogin(function()
	C_Timer.NewTicker(60, P.CheckAll)
end)
