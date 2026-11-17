package.path = "./tests/?.lua;" .. package.path
math.randomseed(1)
local W = require("wow")
local function J(v, ind)
	local t = type(v)
	if t == "table" then
		local isArr = #v > 0 or next(v) == nil
		local parts = {}
		if isArr then for _, x in ipairs(v) do parts[#parts+1] = J(x) end return "[" .. table.concat(parts, ",") .. "]" end
		local keys = {}
		for k in pairs(v) do keys[#keys+1] = tostring(k) end
		table.sort(keys)
		for _, k in ipairs(keys) do local x = v[k] if x == nil then x = v[tonumber(k)] end parts[#parts+1] = string.format("%q", k) .. ":" .. J(x) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\t', ' ') .. '"'
	elseif t == "number" then return string.format("%.6g", v)
	elseif t == "boolean" then return tostring(v) end
	return "null"
end
local out = {}
local w = W.New({ addonDir = ".", epoch = 1795291200 })
local c = w:NewClient({ name = "Corvin" })
c:Login()
w:Advance(30)
local ns = c.ns
ns.db.ui.welcomed = true
c:Slash("demo")
local g = ns.db.guilds["~demo"]
local function board(metric, period, perHour)
	local data, unranked, m, useRate = ns.BuildBoard(g, metric, period, perHour, 0)
	local ch = ns.RankChanges(g, data, m.key, period, perHour, 0)
	local rows = {}
	for i, d in ipairs(data) do
		rows[i] = { rank = i, name = d.name, class = d.class, level = d.level, value = ns.FormatValue(m, d.value, useRate, true),
			raw = d.value, played = ns.FormatTime(d.playtime), change = ch[d.key] and tostring(ch[d.key]) or "", mvp = ns.Hall.MVPCount(g, d.key) }
	end
	return { rows = rows, header = m.key == "score" and "Score" or (useRate and m.short .. "/h" or m.short), desc = ns.PeriodDescription(period, g), metric = m.short }
end
out.score = board("score", "week", false)
out.gold = board("gold", "week", true)
out.damage = board("damage", "week", true)
out.reset = ns.ResetDescription(g)
local mvp, spoon = ns.WeeklyAwards(g)
out.mvp = mvp and { name = mvp.name, class = mvp.class, score = mvp.score }
out.spoon = spoon and { name = spoon.name, class = spoon.class, score = spoon.score }
local leader, cm = ns.ChallengeLeader(g, "week")
out.challenge = { metric = cm and cm.short, leader = leader and leader.name, class = leader and leader.class, prize = g.rules.challengePrize }
local cur, target, gm = ns.GoalProgress(g, "week")
out.goal = { cur = ns.FormatValue(gm, cur, false, true), target = ns.FormatValue(gm, target, false, true), short = gm.short, pct = cur / target }
local rec = ns.Hall.Records(g)
out.hall = { weeks = rec.weeks, mvps = {}, best = {}, streaks = {} }
for i, r in ipairs(rec.mvps) do out.hall.mvps[i] = { name = ns.ShortName(r.key), n = r.n, class = g.players[r.key].class } end
for i, r in ipairs(rec.best) do local m = ns.METRIC_BY_KEY[r.metric]; out.hall.best[i] = { metric = m.short, name = ns.ShortName(r.key), class = g.players[r.key].class, value = ns.FormatValue(m, r.value, m.rate, true), from = r.from } end
for i, r in ipairs(rec.streaks) do out.hall.streaks[i] = { name = ns.ShortName(r.key), n = r.n, current = r.current, class = g.players[r.key].class } end
out.hallweeks = {}
for i, s in ipairs(ns.Hall.Weeks(g)) do if i <= 6 then out.hallweeks[i] = { from = s.from, mvp = ns.ShortName(s.mvp or "?"), n = s.n } end end
out.discord = table.concat(ns.BuildDiscordText(g, "lastweek"), "\n")
out.metrics = {}
for i, m in ipairs(ns.METRICS) do out.metrics[i] = m.short end
ns.UI.Show("hall")
local _, wv = ns.UI.Internals()
out.hallText = wv.hallText:GetText()
io.write(J(out))
