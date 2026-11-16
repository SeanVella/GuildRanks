-- Guild Ranks: the "Me" tab (your stats, daily chart, goals, personal bests, rival,
-- titles) and the session recap window
local ADDON, ns = ...
local L = ns.L
local MeView = {}
ns.MeView = MeView
local P = ns.Personal

local v, el = nil, {}
local M = function(key) return ns.METRIC_BY_KEY[key] end

local PERIOD_CHIPS = { { "today", L["Today"], 50 }, { "week", L["This week"], 70 }, { "all", L["All time"], 62 } }
local CHART = {
	{ value = "goldph", text = L["Gold/h"] }, { value = "xpph", text = L["XP/h"] }, { value = "gold", text = L["Gold"] },
	{ value = "xp", text = L["Experience"] }, { value = "played", text = L["Play time"] }, { value = "quests", text = L["Quests"] },
}

local function H() return ns.UI.H end

local function Chip(parent, text, width, onClick)
	local c = CreateFrame("Button", nil, parent)
	c:SetSize(width, 20)
	c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints()
	c.text = H().FS(c, "GameFontHighlightSmall", "CENTER"); c.text:SetPoint("CENTER"); c.text:SetText(text)
	local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
	c.SetSelected = function(self, on)
		if on then self.bg:SetColorTexture(0.45, 0.36, 0.08, 0.9); self.text:SetTextColor(1, 0.82, 0)
		else self.bg:SetColorTexture(0.16, 0.16, 0.18, 0.9); self.text:SetTextColor(0.85, 0.82, 0.75) end
	end
	c:SetScript("OnClick", onClick)
	return c
end

local function Bar(parent, width)
	local bg = parent:CreateTexture(nil, "ARTWORK"); bg:SetSize(width, 6); bg:SetColorTexture(0.16, 0.17, 0.2, 1)
	local fill = parent:CreateTexture(nil, "OVERLAY"); fill:SetPoint("LEFT", bg, "LEFT"); fill:SetSize(1, 6)
	fill:SetColorTexture(0.79, 0.64, 0.15, 1)
	bg.fill, bg.width = fill, width
	bg.SetFrac = function(self, f) self.fill:SetWidth(math.max(1, self.width * math.max(0, math.min(1, f or 0)))) end
	return bg
end

local function SmallButton(parent, text, width, onClick)
	local b = H().MakeButton(parent, text, width, onClick)
	b:SetHeight(18)
	return b
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function MeView.Build(frame)
	v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", 0, -68)
	v:SetPoint("BOTTOMRIGHT", 0, 56)
	v:Hide()
	local FS = H().FS

	-- Header: name, title, rank; period chips
	el.name = FS(v, "GameFontHighlightLarge"); el.name:SetPoint("TOPLEFT", 20, -8)
	el.title = FS(v, "GameFontNormalSmall"); el.title:SetPoint("LEFT", el.name, "RIGHT", 8, 0)
	el.info = FS(v, "GameFontDisableSmall"); el.info:SetPoint("LEFT", el.title, "RIGHT", 8, 0); el.info:SetWidth(170)
	el.chips = {}
	local x = 578
	for i = #PERIOD_CHIPS, 1, -1 do
		local key, text, width = PERIOD_CHIPS[i][1], PERIOD_CHIPS[i][2], PERIOD_CHIPS[i][3]
		x = x - width
		local c = Chip(v, text, width, function() ns.db.ui.mePeriod = key; ns.UI.Refresh() end)
		c:SetPoint("TOPLEFT", x, -6)
		el.chips[key] = c
		x = x - 4
	end

	-- Stat tiles
	el.tiles = {}
	for i = 1, 5 do
		local t = CreateFrame("Frame", nil, v)
		t:SetSize(106, 50)
		t:SetPoint("TOPLEFT", 18 + (i - 1) * 112, -32)
		local bg = t:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.11, 0.12, 0.14, 0.9)
		t.label = FS(t, "GameFontDisableSmall"); t.label:SetPoint("TOPLEFT", 6, -5); t.label:SetWidth(96)
		t.value = FS(t, "GameFontHighlightLarge"); t.value:SetPoint("TOPLEFT", 6, -18); t.value:SetWidth(96)
		t.change = FS(t, "GameFontHighlightSmall"); t.change:SetPoint("TOPLEFT", 6, -36); t.change:SetWidth(96)
		el.tiles[i] = t
	end

	-- Daily chart (last 7 days)
	el.bars, el.dayLabels = {}, {}
	local bw = 72
	for i = 1, 7 do
		local bx = 18 + (i - 1) * (bw + 8)
		local b = v:CreateTexture(nil, "ARTWORK")
		b:SetPoint("BOTTOMLEFT", v, "TOPLEFT", bx, -150)
		b:SetSize(bw, 1)
		el.bars[i] = b
		local lab = FS(v, "GameFontDisableSmall", "CENTER")
		lab:SetPoint("TOPLEFT", bx, -152); lab:SetWidth(bw)
		el.dayLabels[i] = lab
	end
	el.chartPick = ns.UI.MakeDropdown(v, 130, function() return CHART end,
		function() return ns.db.ui.meChart or "goldph" end, function(val) ns.db.ui.meChart = val; ns.UI.Refresh() end)
	el.chartPick:SetPoint("TOPLEFT", 16, -166)
	el.chartNote = FS(v, "GameFontDisableSmall", "RIGHT"); el.chartNote:SetPoint("TOPRIGHT", -24, -172); el.chartNote:SetWidth(300)

	-- Left column: goals and personal bests
	local L1 = 18
	el.goalsHead = FS(v, "GameFontNormal"); el.goalsHead:SetPoint("TOPLEFT", L1 + 2, -198); el.goalsHead:SetText(L["Goals"])
	el.addGoal = SmallButton(v, L["+ Add goal"], 90, function() el.adding = true; ns.UI.Refresh() end)
	el.addGoal:SetPoint("TOPLEFT", L1 + 180, -194)
	el.goalHint = FS(v, "GameFontDisableSmall"); el.goalHint:SetPoint("TOPLEFT", L1 + 2, -218); el.goalHint:SetWidth(260)
	el.goalHint:SetWordWrap(true)
	el.goalHint:SetText(L["Set a goal for this week or month, or a level to reach."])
	el.goals = {}
	for i = 1, P.MAX_GOALS do
		local row = { y = -216 - (i - 1) * 32 }
		row.label = FS(v, "GameFontHighlightSmall"); row.label:SetPoint("TOPLEFT", L1 + 2, row.y); row.label:SetWidth(130)
		row.status = FS(v, "GameFontHighlightSmall", "RIGHT"); row.status:SetPoint("TOPLEFT", L1 + 132, row.y); row.status:SetWidth(118)
		row.bar = Bar(v, 250); row.bar:SetPoint("TOPLEFT", L1 + 2, row.y - 15)
		row.remove = SmallButton(v, "x", 18, function() P.RemoveGoal(i); ns.UI.Refresh() end)
		row.remove:SetPoint("TOPLEFT", L1 + 254, row.y + 2)
		el.goals[i] = row
	end
	-- add-goal form
	el.form = CreateFrame("Frame", nil, v)
	el.form:SetSize(270, 52)
	el.newGoal = { kind = "gold", period = "week" }
	el.formKind = ns.UI.MakeDropdown(el.form, 130, function() return P.GOAL_TYPES end,
		function() return el.newGoal.kind end, function(val) el.newGoal.kind = val; ns.UI.Refresh() end)
	el.formKind:SetPoint("TOPLEFT", 0, 0)
	el.formTarget = CreateFrame("EditBox", nil, el.form, "InputBoxTemplate")
	el.formTarget:SetSize(60, 20); el.formTarget:SetPoint("TOPLEFT", 140, -2)
	el.formTarget:SetAutoFocus(false); el.formTarget:SetNumeric(true); el.formTarget:SetMaxLetters(7)
	el.formUnit = FS(el.form, "GameFontHighlightSmall"); el.formUnit:SetPoint("LEFT", el.formTarget, "RIGHT", 4, 0)
	el.formPeriod = ns.UI.MakeDropdown(el.form, 110, function()
		return { { value = "week", text = L["This week"] }, { value = "month", text = L["This month"] } }
	end, function() return el.newGoal.period end, function(val) el.newGoal.period = val end)
	el.formPeriod:SetPoint("TOPLEFT", 0, -26)
	el.formAdd = SmallButton(el.form, L["Add"], 60, function()
		if P.AddGoal(el.newGoal.kind, el.formTarget:GetText(), el.newGoal.period) then
			el.adding = false
			el.formTarget:SetText("")
		else
			ns.Print(L["Enter a target above where you are now."])
		end
		ns.UI.Refresh()
	end)
	el.formAdd:SetPoint("TOPLEFT", 120, -28)
	el.formCancel = SmallButton(el.form, L["Cancel"], 70, function() el.adding = false; ns.UI.Refresh() end)
	el.formCancel:SetPoint("LEFT", el.formAdd, "RIGHT", 6, 0)
	el.formTarget:SetScript("OnEnterPressed", function() el.formAdd:GetScript("OnClick")(el.formAdd) end)

	el.bestsHead = FS(v, "GameFontNormal"); el.bestsHead:SetPoint("TOPLEFT", L1 + 2, -340); el.bestsHead:SetText(L["Personal bests"])
	el.bests = {}
	for i, rec in ipairs(P.RECORDS) do
		local y = -358 - (i - 1) * 15
		local l = FS(v, "GameFontHighlightSmall"); l:SetPoint("TOPLEFT", L1 + 2, y); l:SetWidth(130); l:SetText(rec.label)
		local r = FS(v, "GameFontHighlightSmall", "RIGHT"); r:SetPoint("TOPLEFT", L1 + 132, y); r:SetWidth(138)
		el.bests[i] = r
	end
	el.recap = H().MakeButton(v, L["Session recap"], 130, function() ns.ShowRecap() end)
	el.recap:SetPoint("TOPLEFT", L1, -476)

	-- Right column: rival and titles
	local R = 306
	el.rivalHead = FS(v, "GameFontNormal"); el.rivalHead:SetPoint("TOPLEFT", R + 2, -198); el.rivalHead:SetWidth(150)
	el.rivalPick = ns.UI.MakeDropdown(v, 110, function()
		local o = { { value = "", text = L["No rival"] } }
		local g = ns.V()
		local names = {}
		if g then for key in pairs(g.players) do if key ~= ns.me then names[#names + 1] = key end end end
		table.sort(names)
		for _, key in ipairs(names) do o[#o + 1] = { value = key, text = ns.ShortName(key) } end
		return o
	end, function() return P.Rival() or "" end, function(val) P.SetRival(val ~= "" and val or nil); ns.UI.Refresh() end, L["Pick a rival"])
	el.rivalPick:SetPoint("TOPLEFT", R + 160, -194)
	el.rivalHint = FS(v, "GameFontDisableSmall"); el.rivalHint:SetPoint("TOPLEFT", R + 2, -220); el.rivalHint:SetWidth(266)
	el.rivalHint:SetWordWrap(true)
	el.rivalHint:SetText(L["Pick a guildmate to race against. You'll get an alert when either of you passes the other."])
	el.youHead = FS(v, "GameFontDisableSmall", "RIGHT"); el.youHead:SetPoint("TOPLEFT", R + 140, -218); el.youHead:SetWidth(60)
	el.youHead:SetText(L["You"])
	el.themHead = FS(v, "GameFontDisableSmall", "RIGHT"); el.themHead:SetPoint("TOPLEFT", R + 205, -218); el.themHead:SetWidth(64)
	el.h2h = {}
	for i = 1, #P.RIVAL_METRICS do
		local y = -233 - (i - 1) * 15
		local row = {}
		row.label = FS(v, "GameFontHighlightSmall"); row.label:SetPoint("TOPLEFT", R + 2, y); row.label:SetWidth(130)
		row.mine = FS(v, "GameFontHighlightSmall", "RIGHT"); row.mine:SetPoint("TOPLEFT", R + 140, y); row.mine:SetWidth(60)
		row.theirs = FS(v, "GameFontHighlightSmall", "RIGHT"); row.theirs:SetPoint("TOPLEFT", R + 205, y); row.theirs:SetWidth(64)
		el.h2h[i] = row
	end
	el.rivalNote = FS(v, "GameFontDisableSmall"); el.rivalNote:SetPoint("TOPLEFT", R + 2, -312); el.rivalNote:SetWidth(266)

	el.titlesHead = FS(v, "GameFontNormal"); el.titlesHead:SetPoint("TOPLEFT", R + 2, -340); el.titlesHead:SetText(L["Titles this week"])
	el.titles = {}
	for i, t in ipairs(P.TITLES) do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local b = CreateFrame("Button", nil, v)
		b:SetSize(86, 18)
		b:SetPoint("TOPLEFT", R + col * 90, -358 - row * 21)
		b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
		b.text = FS(b, "GameFontHighlightSmall", "CENTER"); b.text:SetPoint("CENTER"); b.text:SetWidth(82); b.text:SetText(t.name)
		local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
		b.code = t.code
		b:SetScript("OnClick", function(self)
			if not self.earned then return end
			P.SetTitle(P.MyTitleCode() == self.code and nil or self.code)
			ns.UI.Refresh()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(t.name)
			local what = t.code == "mvp" and L["last week's MVP"]
				or (t.code == "deaths" and L["no deaths last week (and the fewest)"])
				or string.format(L["#1 in %s last week"], (M(t.metric).short or t.metric) .. "/h")
			GameTooltip:AddLine(what, 1, 1, 1, true)
			if self.earned then
				GameTooltip:AddLine(P.MyTitleCode() == self.code and L["Shown to your guild. Click to hide."] or L["Click to show it to your guild."], 0.4, 1, 0.4)
			else
				GameTooltip:AddLine(L["Not earned this week."], 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		el.titles[i] = b
	end
	el.titleNote = FS(v, "GameFontDisableSmall"); el.titleNote:SetPoint("TOPLEFT", R + 2, -466); el.titleNote:SetWidth(266)
	el.titleNote:SetWordWrap(true)
	return v
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function Rate(total, secs) return secs > 0 and total / (secs / 3600) or 0 end

local function Pct(now, before)
	if not before or before <= 0 then return "" end
	local pct = math.floor((now - before) / before * 100 + 0.5)
	if pct > 0 then return "|cff40ff40+" .. pct .. "%|r" elseif pct < 0 then return "|cffff5050" .. pct .. "%|r" end
	return "|cff808080=|r"
end

local function Diff(now, before, fmt)
	if before == nil then return "" end
	local d = now - before
	local s = fmt and fmt(math.abs(d)) or tostring(math.floor(math.abs(d) + 0.5))
	if d > 0.0001 then return "|cff40ff40+" .. s .. "|r" elseif d < -0.0001 then return "|cffff5050-" .. s .. "|r" end
	return "|cff808080=|r"
end

local function DayChartValue(kind, b)
	local secs = b.playtime or 0
	if kind == "goldph" then return Rate(P.Value(b, "gold"), secs)
	elseif kind == "xpph" then return Rate(b.xp or 0, secs)
	elseif kind == "gold" then return P.Value(b, "gold")
	elseif kind == "xp" then return b.xp or 0
	elseif kind == "played" then return secs
	elseif kind == "quests" then return b.quests or 0 end
	return 0
end

local function DayChartText(kind, val)
	if kind == "goldph" then return ns.FormatMoney(val) .. "/h"
	elseif kind == "gold" then return ns.FormatMoney(val)
	elseif kind == "xpph" then return ns.FormatNumber(val) .. "/h"
	elseif kind == "played" then return ns.FormatTime(val) end
	return ns.FormatNumber(val)
end

function MeView.Refresh(g)
	if not v then return end
	local period = ns.db.ui.mePeriod or "week"
	local p = g.players[ns.me]
	local cls = p and p.class or select(2, UnitClass("player"))
	el.name:SetText(H().ClassColored(ns.ShortName(ns.me or "?"), cls))
	local shown = P.ShownTitle(g, ns.me)
	el.title:SetText(shown and ("<" .. shown.name .. ">") or "")
	local scores = ns.ComputeScores(g, period, 0)
	local rank
	for i, e in ipairs(scores) do if e.key == ns.me then rank = i end end
	local per = ns.PERIOD_BY_KEY[period] or ns.PERIODS[2]
	el.info:SetText(string.format(L["level %d"], UnitLevel("player") or (p and p.level) or 0)
		.. (rank and ("  ·  " .. per.label:lower() .. " #" .. rank .. " " .. string.format(L["of %d"], #scores)) or ""))
	for key, c in pairs(el.chips) do c:SetSelected(key == period) end

	-- Tiles with change vs the previous period
	local b = P.Bucket(period)
	local prevPeriod = ns.PreviousPeriod(period, g)
	local pb = (prevPeriod and p) and ns.Aggregate(p, prevPeriod, g) or nil
	local secs, psecs = b.playtime or 0, pb and (pb.playtime or 0) or nil
	local vsText = period == "today" and L["vs yesterday"] or (period == "week" and L["vs last week"] or "")
	local gph, xph = Rate(P.Value(b, "gold"), secs), Rate(b.xp or 0, secs)
	local tiles = {
		{ L["Played"], ns.FormatTime(secs), Diff(secs, psecs, ns.FormatTime) },
		{ L["Gold/h"], ns.FormatMoney(gph), pb and (Pct(gph, Rate(P.Value(pb, "gold"), psecs)) .. " " .. vsText) or "" },
		{ L["XP/h"], ns.FormatNumber(xph), pb and Pct(xph, Rate(pb.xp or 0, psecs)) or "" },
		{ L["Levels"], string.format("%.2f", P.Value(b, "levels")), pb and Diff(P.Value(b, "levels"), P.Value(pb, "levels"), function(x) return string.format("%.2f", x) end) or "" },
		{ L["Quests"], tostring(b.quests or 0), pb and Diff(b.quests or 0, pb.quests or 0) or "" },
	}
	for i, t in ipairs(tiles) do
		el.tiles[i].label:SetText(t[1]); el.tiles[i].value:SetText(t[2]); el.tiles[i].change:SetText(t[3])
	end

	-- Chart: last 7 days
	local kind = ns.db.ui.meChart or "goldph"
	local today = ns.Today()
	local vals, max = {}, 0
	for i = 1, 7 do
		local day = ns.ShiftDay(today, i - 7)
		local val = (p and p.days[day]) and DayChartValue(kind, p.days[day]) or 0
		vals[i] = val
		if val > max then max = val end
		local t = ns.KeyToTime(day)
		el.dayLabels[i]:SetText(i == 7 and L["Today"] or (t and date("%a", t) or ""))
	end
	for i = 1, 7 do
		local h = max > 0 and math.max(vals[i] > 0 and 2 or 1, 56 * vals[i] / max) or 1
		el.bars[i]:SetHeight(h)
		if i == 7 then el.bars[i]:SetColorTexture(0.79, 0.64, 0.15, 1) else el.bars[i]:SetColorTexture(0.36, 0.29, 0.1, 1) end
	end
	el.chartPick:Refresh()
	el.chartNote:SetText(L["Today"] .. ": " .. DayChartText(kind, vals[7]))

	-- Goals
	local d = P.Data() or { goals = {}, records = {} }
	local n = #d.goals
	for i, row in ipairs(el.goals) do
		local goal = d.goals[i]
		local on = goal ~= nil
		row.label:SetShown(on); row.status:SetShown(on); row.bar:SetShown(on); row.bar.fill:SetShown(on); row.remove:SetShown(on)
		if on then
			local _, frac, status = P.GoalProgress(goal)
			row.label:SetText(P.GoalLabel(goal))
			row.status:SetText(status)
			row.bar:SetFrac(frac)
		end
	end
	el.goalHint:SetShown(n == 0 and not el.adding)
	el.addGoal:SetShown(n < P.MAX_GOALS and not el.adding)
	el.form:SetShown(el.adding and n < P.MAX_GOALS)
	el.form:ClearAllPoints()
	el.form:SetPoint("TOPLEFT", 20, -216 - n * 32)
	el.formPeriod:SetShown(el.newGoal.kind ~= "level")
	el.formUnit:SetText(el.newGoal.kind == "gold" and L["gold"] or (el.newGoal.kind == "level" and L["level"] or ""))

	-- Personal bests
	local streak = P.Streak()
	for i, rec in ipairs(P.RECORDS) do
		local r = d.records[rec.key]
		if not r then
			el.bests[i]:SetText("|cff808080-|r")
		else
			local when
			if rec.key == "streak" then
				when = (streak > 0 and streak >= r.value) and L["ongoing"] or (L["now"] .. " " .. streak)
			else
				local t = ns.KeyToTime(r.day)
				when = r.day == today and L["today"] or (t and date("%d %b", t) or r.day)
			end
			el.bests[i]:SetText(P.FormatRecord(rec, r.value) .. "  |cff808080" .. when .. "|r")
		end
	end

	-- Rival
	local rival = P.Rival()
	local hasRival = rival ~= nil and not g.solo
	el.rivalPick:Refresh()
	el.rivalPick:SetShown(not g.solo)
	local rp = rival and g.players[rival]
	el.rivalHead:SetText(hasRival and (L["Rival"] .. ": " .. H().ClassColored(ns.ShortName(rival), rp and rp.class)) or L["Rival"])
	el.rivalHint:SetShown(not hasRival)
	if g.solo then el.rivalHint:SetText(L["Join a guild to pick a rival."]) end
	el.youHead:SetShown(hasRival); el.themHead:SetShown(hasRival); el.rivalNote:SetShown(hasRival)
	local leads, rows = 0, hasRival and P.HeadToHead(g, period == "all" and "all" or period) or {}
	el.themHead:SetText(hasRival and ns.ShortName(rival) or "")
	for i, row in ipairs(el.h2h) do
		local h = rows[i]
		row.label:SetShown(h ~= nil); row.mine:SetShown(h ~= nil); row.theirs:SetShown(h ~= nil)
		if h then
			local function fmt(val) return val and ns.FormatValue(h.metric, val, h.perHour) or "|cff808080-|r" end
			local mineBetter = h.mine and (not h.theirs or h.mine > h.theirs)
			local theirsBetter = h.theirs and (not h.mine or h.theirs > h.mine)
			if mineBetter then leads = leads + 1 end
			row.label:SetText(h.label)
			row.mine:SetText(mineBetter and ("|cff40ff40" .. fmt(h.mine) .. "|r") or fmt(h.mine))
			row.theirs:SetText(theirsBetter and ("|cff40ff40" .. fmt(h.theirs) .. "|r") or fmt(h.theirs))
		end
	end
	el.rivalNote:SetText(string.format(L["You lead %d of %d"], leads, #rows))

	-- Titles
	local mine = {}
	for _, t in ipairs(P.TitlesFor(g, ns.me)) do mine[t.code] = true end
	local chosen, any = P.MyTitleCode(), false
	for _, b2 in ipairs(el.titles) do
		b2.earned = mine[b2.code] or false
		if b2.earned then any = true end
		if b2.earned and chosen == b2.code then
			b2.bg:SetColorTexture(0.55, 0.43, 0.08, 0.95); b2.text:SetTextColor(1, 0.9, 0.4)
		elseif b2.earned then
			b2.bg:SetColorTexture(0.3, 0.24, 0.06, 0.9); b2.text:SetTextColor(1, 0.82, 0)
		else
			b2.bg:SetColorTexture(0.12, 0.12, 0.13, 0.9); b2.text:SetTextColor(0.4, 0.38, 0.35)
		end
	end
	el.titleNote:SetText(any and L["Click one of your titles to show it to your guild."]
		or L["Finish #1 in a ranking this week to earn its title for next week."])
end

---------------------------------------------------------------------------
-- Session recap window
---------------------------------------------------------------------------
local recap
local function CreateRecap()
	recap = CreateFrame("Frame", "GuildRanksRecap", UIParent, "BackdropTemplate")
	recap:SetSize(380, 170)
	recap:SetPoint("CENTER", 0, 160)
	recap:SetFrameStrata("DIALOG")
	recap:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	recap:EnableMouse(true); recap:SetMovable(true); recap:RegisterForDrag("LeftButton")
	recap:SetScript("OnDragStart", recap.StartMoving); recap:SetScript("OnDragStop", recap.StopMovingOrSizing)
	recap:Hide()
	tinsert(UISpecialFrames, "GuildRanksRecap")
	local close = CreateFrame("Button", nil, recap, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
	recap.title = H().FS(recap, "GameFontNormalLarge"); recap.title:SetPoint("TOPLEFT", 22, -18)
	recap.body = H().FS(recap, "GameFontHighlight"); recap.body:SetPoint("TOPLEFT", 22, -44)
	recap.body:SetWidth(336); recap.body:SetWordWrap(true); recap.body:SetSpacing(3)
	recap.post = H().MakeButton(recap, L["Post in guild chat"], 150, function()
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		if IsInGuild() and recap.chat and send then send(recap.chat, "GUILD") end
		recap:Hide()
	end)
	recap.post:SetPoint("BOTTOMLEFT", 20, 18)
	local ok = H().MakeButton(recap, L["Close"], 80, function() recap:Hide() end)
	ok:SetPoint("BOTTOMRIGHT", -20, 18)
end

-- Show a session (default: this session if it has a minute of play, else the last one)
function ns.ShowRecap(s, isLast)
	if not s then
		local cur = P.CurrentSession()
		if ((cur.totals or {}).playtime or 0) >= 60 then
			s, isLast = cur, false
		else
			s, isLast = P.LastSession(), true
		end
	end
	if not s then
		ns.Print(L["No session to show yet. Play a little first."])
		return false
	end
	if not recap then CreateRecap() end
	local lines, chat = P.SessionLines(s)
	recap.title:SetText(isLast and (L["Last session"] .. "  ·  " .. date("%a %H:%M", s.finish or time())) or L["This session so far"])
	recap.body:SetText(table.concat(lines, "\n"))
	recap.chat = chat
	recap:SetHeight(110 + #lines * 16)
	if IsInGuild() then recap.post:Enable() else recap.post:Disable() end
	recap:Show()
	return true
end

function MeView.RecapText() return recap and recap:IsShown() and recap.body:GetText() end -- for the automated tests
function MeView.Internals() return el end -- for the automated tests
