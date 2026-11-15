-- Guild Ranks: Hall of Fame. Each finished week is saved as a snapshot (scores,
-- ranks, MVP, best per ranking, challenge winner), so records, MVP badges and
-- player history survive after the daily data is pruned.
local ADDON, ns = ...
local L = ns.L
local H = {}
ns.Hall = H

local WEEKS_BACK = 8      -- how far back to build snapshots from daily data
local RECORD_METRICS = { "gold", "loot", "xp", "levels", "damage", "healing", "kills", "quests", "bosses", "dungeons", "gathers", "crafts" }

local function Snapshot(g, from, to)
	local range = { from = from, to = to }
	local scores = ns.ComputeScores(g, range, 0)
	if #scores == 0 then return nil end
	local snap = { from = from, to = to, n = #scores, scores = {}, ranks = {}, best = {} }
	for i, e in ipairs(scores) do
		snap.scores[e.key] = e.score
		snap.ranks[e.key] = i
	end
	snap.mvp = scores[1].key
	if #scores >= 2 then snap.spoon = scores[#scores].key end
	for _, key in ipairs(RECORD_METRICS) do
		local rows = ns.BuildBoard(g, key, range, true, 0)
		if rows[1] then snap.best[key] = { key = rows[1].key, value = rows[1].value } end
	end
	local cm = g.rules.challengeMetric
	if cm and ns.METRIC_BY_KEY[cm] then
		local rows = ns.BuildBoard(g, cm, range, true, 0)
		if rows[1] then snap.challenge = { metric = cm, key = rows[1].key, value = rows[1].value, prize = g.rules.challengePrize } end
	end
	return snap
end

-- Build or refresh snapshots of finished weeks. Last week is refreshed every
-- time (late data can still arrive); older weeks are built once.
function H.Update(g)
	if not g then return end
	g.hall = g.hall or { weeks = {} }
	local thisStart = ns.WeekStart(g)
	for i = 1, WEEKS_BACK do
		local from = ns.ShiftDay(thisStart, -7 * i)
		local to = ns.ShiftDay(from, 7)
		if i == 1 or not g.hall.weeks[from] then
			local snap = Snapshot(g, from, to)
			if snap then g.hall.weeks[from] = snap end
		end
	end
end

-- Snapshots sorted newest first
function H.Weeks(g)
	local list = {}
	for from, snap in pairs((g.hall and g.hall.weeks) or {}) do
		if snap.n and snap.n > 0 then list[#list + 1] = snap end
	end
	table.sort(list, function(a, b) return a.from > b.from end)
	return list
end

function H.MVPCount(g, key)
	local n = 0
	for _, snap in ipairs(H.Weeks(g)) do
		if snap.mvp == key and snap.n >= 2 then n = n + 1 end
	end
	return n
end

-- Trophy icon(s) for players who have been MVP
function H.Badge(g, key)
	local n = H.MVPCount(g, key)
	if n <= 0 then return "" end
	local icon = "|TInterface\\Icons\\INV_Misc_Trophy_Gold:12:12|t"
	return " " .. icon .. (n > 1 and ("x" .. n) or "")
end

-- Records across all saved weeks
function H.Records(g)
	local weeks = H.Weeks(g)
	local rec = { mvps = {}, best = {}, streaks = {}, weeks = #weeks }
	-- MVP counts
	local counts = {}
	for _, snap in ipairs(weeks) do
		if snap.n >= 2 then counts[snap.mvp] = (counts[snap.mvp] or 0) + 1 end
	end
	for key, n in pairs(counts) do rec.mvps[#rec.mvps + 1] = { key = key, n = n } end
	table.sort(rec.mvps, function(a, b) return a.n == b.n and a.key < b.key or a.n > b.n end)
	-- Best week per ranking
	for _, metricKey in ipairs(RECORD_METRICS) do
		local top
		for _, snap in ipairs(weeks) do
			local b = snap.best and snap.best[metricKey]
			if b and (not top or b.value > top.value) then top = { key = b.key, value = b.value, from = snap.from } end
		end
		if top then rec.best[#rec.best + 1] = { metric = metricKey, key = top.key, value = top.value, from = top.from } end
	end
	-- Longest run of consecutive weeks in the top 3 (oldest to newest)
	local runs, best = {}, {}
	for i = #weeks, 1, -1 do
		local snap = weeks[i]
		local seen = {}
		for key, rank in pairs(snap.ranks) do
			if rank <= 3 then
				runs[key] = (runs[key] or 0) + 1
				best[key] = math.max(best[key] or 0, runs[key])
				seen[key] = true
			end
		end
		for key in pairs(runs) do
			if not seen[key] then runs[key] = 0 end
		end
	end
	for key, n in pairs(best) do
		if n >= 2 then rec.streaks[#rec.streaks + 1] = { key = key, n = n, current = runs[key] or 0 } end
	end
	table.sort(rec.streaks, function(a, b) return a.n == b.n and a.key < b.key or a.n > b.n end)
	return rec
end

-- A player's recent weeks: { from, rank, score, n } newest first (max count)
function H.History(g, key, count)
	local list = {}
	for _, snap in ipairs(H.Weeks(g)) do
		if snap.ranks[key] then
			list[#list + 1] = { from = snap.from, rank = snap.ranks[key], score = snap.scores[key], n = snap.n }
			if #list >= (count or 6) then break end
		end
	end
	return list
end

-- Rank and score in the previous week's snapshot before `from` (for "up 3 places")
function H.PreviousRank(g, key, from)
	local prev = ns.ShiftDay(from, -7)
	local snap = g.hall and g.hall.weeks[prev]
	return snap and snap.ranks[key], snap and snap.scores[key]
end

-- Background version: one week per step, so building many weeks never freezes the game
function H.UpdateGradually(g, i)
	if not g then return end
	i = i or 1
	g.hall = g.hall or { weeks = {} }
	local thisStart = ns.WeekStart(g)
	while i <= WEEKS_BACK do
		local from = ns.ShiftDay(thisStart, -7 * i)
		if i == 1 or not g.hall.weeks[from] then
			local snap = Snapshot(g, from, ns.ShiftDay(from, 7))
			if snap then g.hall.weeks[from] = snap end
			if i < WEEKS_BACK then C_Timer.After(0.3, function() H.UpdateGradually(g, i + 1) end) end
			return
		end
		i = i + 1
	end
end

-- Keep snapshots fresh in the background
ns.OnGuildChanged(function() C_Timer.After(15, function() H.UpdateGradually(ns.G()) end) end)
ns.OnLogin(function()
	C_Timer.NewTicker(600, function()
		if ns.G() then H.UpdateGradually(ns.G()) end
	end)
end)
