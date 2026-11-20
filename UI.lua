-- Guild Ranks: main window (tabs: ranks, Hall of Fame, members, settings), slash commands
local ADDON, ns = ...
local L = ns.L
local UI = {}
ns.UI = UI

local ROW_H = 20
local BAR_W = 96
local frame, views, current = nil, {}, "list"
local subtitle, footerText, valueHeader, changeHeader, emptyText, content
local titleText, guildText, resetText
local rows, memberRows = {}, {}
local controls, w, tabs = {}, {}, {}
local CreateMain -- defined below

---------------------------------------------------------------------------
-- Widget helpers (also used by Panels.lua through ns.UI.H)
---------------------------------------------------------------------------
local function FS(parent, font, justify)
	local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	f:SetJustifyH(justify or "LEFT")
	f:SetWordWrap(false)
	return f
end

local function ClassColored(name, class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
	return name
end

-- Tooltip on hover (keeps any existing OnEnter/OnLeave of templates)
local function Tip(f, title, text)
	if not f then return end
	local function enter(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end
	local function leave() GameTooltip:Hide() end
	if f.HookScript then
		f:HookScript("OnEnter", enter)
		f:HookScript("OnLeave", leave)
	else
		f:SetScript("OnEnter", enter)
		f:SetScript("OnLeave", leave)
	end
end

-- Modern dropdown, with a click-to-cycle button as a fallback
local function MakeDropdown(parent, width, getOptions, getValue, setValue, defaultText)
	local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dd and dd.SetupMenu then
		dd:SetWidth(width)
		if defaultText and dd.SetDefaultText then dd:SetDefaultText(defaultText) end
		dd:SetupMenu(function(_, root)
			for _, opt in ipairs(getOptions()) do
				root:CreateRadio(opt.text,
					function() return getValue() == opt.value end,
					function() setValue(opt.value) end)
			end
		end)
		dd.Refresh = function(self) if self.GenerateMenu then self:GenerateMenu() end end
		return dd
	end
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b.Refresh = function(self)
		local text = defaultText or ""
		for _, o in ipairs(getOptions()) do
			if o.value == getValue() then text = o.text end
		end
		self:SetText(text)
	end
	b:SetScript("OnClick", function(self)
		local opts, idx = getOptions(), 0
		for i, o in ipairs(opts) do
			if o.value == getValue() then idx = i end
		end
		if #opts > 0 then setValue(opts[idx % #opts + 1].value) end
		self:Refresh()
	end)
	b:Refresh()
	return b
end

local function MakeCheck(parent, label, onClick, tip)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb.label = FS(cb, "GameFontHighlight")
	cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb.label:SetText(label)
	cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	if tip then Tip(cb, label, tip) end
	return cb
end

local function MakeButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function Label(parent, text, x, y, font)
	local f = FS(parent, font or "GameFontNormalSmall")
	f:SetPoint("TOPLEFT", x, y)
	f:SetText(text)
	return f
end

local function MakeScroll(parent, top, width)
	local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
	if not ok or not sf then sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate") end
	sf:SetPoint("TOPLEFT", 18, top)
	sf:SetPoint("BOTTOMRIGHT", -38, 0)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(width or 530, 1)
	sf:SetScrollChild(child)
	return sf, child
end

-- A flat tab: label, gold underline when selected
local function MakeTab(parent, text, width, onClick, small)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, small and 20 or 24)
	b.text = FS(b, small and "GameFontHighlightSmall" or "GameFontHighlight", "CENTER")
	b.text:SetPoint("CENTER", 0, 1)
	b.text:SetText(text)
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetPoint("BOTTOMLEFT", 4, 0)
	b.line:SetPoint("BOTTOMRIGHT", -4, 0)
	b.line:SetHeight(2)
	b.line:SetColorTexture(1, 0.82, 0, 1)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)
	b.SetSelected = function(self, on)
		if on then self.text:SetTextColor(1, 0.82, 0) else self.text:SetTextColor(0.75, 0.72, 0.66) end
		self.line:SetShown(on)
	end
	b:SetScript("OnClick", onClick)
	b:SetSelected(false)
	return b
end

-- How many roster members use the addon: with, total (nil when unknown)
function UI.AddonUsers(g)
	if not g or g.solo or g ~= ns.G() or not ns.rosterReady then return nil end
	local with = 0
	for key in pairs(ns.roster) do if g.players[key] then with = with + 1 end end
	return with, ns.rosterCount
end

-- Online status from the guild roster: true / false, or nil when we can't tell
-- (another character's guild, sample data, roster not loaded yet)
function UI.RosterKnown(g)
	return g ~= nil and not g.solo and g == ns.G() and ns.rosterReady and true or false
end

function UI.IsOnline(g, key)
	if not UI.RosterKnown(g) then return nil end
	local info = ns.roster[key]
	return info and info.online and true or false
end

function UI.OnlineCount(g)
	if not UI.RosterKnown(g) then return nil end
	local n = 0
	for _, info in pairs(ns.roster) do if info.online then n = n + 1 end end
	return n
end

local ONLINE_ICON = "|T" .. (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online") .. ":12:12|t "
local OFFLINE_ICON = "|T" .. (FRIENDS_TEXTURE_OFFLINE or "Interface\\FriendsFrame\\StatusIcon-Offline") .. ":12:12|t "

UI.H = { FS = FS, ClassColored = ClassColored, Tip = Tip, MakeButton = MakeButton, MakeScroll = MakeScroll }
UI.MakeDropdown = MakeDropdown
function UI.Frame() return frame end
function UI.Internals() return controls, w, tabs, footerText end -- for the automated tests
function UI.VisibleRows() -- for the automated tests
	local out = {}
	for _, r in ipairs(rows) do
		if r:IsShown() and r.data then out[#out + 1] = { key = r.data.key, rank = r.rank:GetText(), name = r.name:GetText() } end
	end
	return out
end
function UI.Current() return current end

---------------------------------------------------------------------------
-- Leaderboard
---------------------------------------------------------------------------
local RANK_COLORS = { "|cffffd700", "|cffc7c7cf", "|cffcd7f32" }
local CHIPS = { "score", "gold", "xp", "damage", "quests" }
local CHIP_W = { score = 54, gold = 50, xp = 40, damage = 64, quests = 60 }

local function ShowRowTooltip(self)
	local d = self.data
	if not d then return end
	local g = ns.V()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ClassColored(d.key, d.class))
	local title = ns.Personal and ns.Personal.ShownTitle(g, d.key)
	if title then GameTooltip:AddLine("<" .. title.name .. ">", 1, 0.82, 0) end
	if ns.PlaytimeShownFor(g, d.key) and d.playtime then
		GameTooltip:AddLine(string.format(L["Level %d  ·  %s played"], d.level or 0, ns.FormatTime(d.playtime)), 0.8, 0.8, 0.8)
	else
		GameTooltip:AddLine(string.format(L["Level %d"], d.level or 0), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine(L["Click for details"], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function GetRow(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Button", nil, content)
	r:SetSize(530, ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 1, 1, 0.08)
	r.rank = FS(r, "GameFontHighlight", "RIGHT"); r.rank:SetPoint("LEFT", 0, 0); r.rank:SetWidth(28)
	r.name = FS(r, "GameFontHighlight", "LEFT"); r.name:SetPoint("LEFT", 36, 0); r.name:SetWidth(200)
	r.level = FS(r, "GameFontHighlight", "CENTER"); r.level:SetPoint("LEFT", 240, 0); r.level:SetWidth(32)
	r.barBg = r:CreateTexture(nil, "ARTWORK")
	r.barBg:SetPoint("LEFT", 282, 0); r.barBg:SetSize(BAR_W, 6)
	r.barBg:SetColorTexture(0.16, 0.17, 0.2, 1)
	r.bar = r:CreateTexture(nil, "OVERLAY")
	r.bar:SetPoint("LEFT", r.barBg, "LEFT", 0, 0); r.bar:SetSize(1, 6)
	r.bar:SetColorTexture(0.79, 0.64, 0.15, 1)
	r.value = FS(r, "GameFontHighlight", "RIGHT"); r.value:SetPoint("LEFT", 380, 0); r.value:SetWidth(60)
	r.change = FS(r, "GameFontHighlightSmall", "RIGHT"); r.change:SetPoint("LEFT", 444, 0); r.change:SetWidth(34)
	r.played = FS(r, "GameFontHighlightSmall", "RIGHT"); r.played:SetPoint("LEFT", 482, 0); r.played:SetWidth(48)
	r:SetScript("OnEnter", ShowRowTooltip)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self)
		if self.data and ns.Card then ns.Card.Toggle(self.data.key) end
	end)
	rows[i] = r
	return r
end

local function ChangeText(c)
	if c == nil then return "" end
	if c == "new" then return "|cff5ac8fa" .. L["new"] .. "|r" end
	if c > 0 then return "|cff40ff40+" .. c .. "|r" end
	if c < 0 then return "|cffff5050" .. c .. "|r" end
	return "|cff808080=|r"
end

-- Award strip: up to three boxes (last week's awards, challenge, goal), only those with something to say
local function LayoutStrip(g)
	local items = {}
	local mvp, spoon = ns.WeeklyAwards(g)
	if mvp then
		local text = string.format(L["MVP last week: %s (%d)"], ClassColored(mvp.name, mvp.class), mvp.score)
		if spoon then text = text .. "  ·  " .. string.format(L["Wooden spoon: %s (%d)"], ClassColored(spoon.name, spoon.class), spoon.score) end
		controls.award:SetText(text)
		items[#items + 1] = controls.awardBox
	end
	local leader, cmetric = ns.ChallengeLeader(g, "week")
	if g.rules.challengeMetric and cmetric then
		local text = string.format(L["Challenge: most %s"], cmetric.short .. "/h")
		if leader then text = text .. "  ·  " .. string.format(L["%s leads"], ClassColored(leader.name, leader.class)) end
		if g.rules.challengePrize then text = text .. "  ·  " .. L["prize"] .. " " .. g.rules.challengePrize end
		controls.challenge:SetText(text)
		items[#items + 1] = controls.challengeBox
	end
	local cur, target, gmetric = ns.GoalProgress(g, "week")
	if cur then
		controls.goal:SetText(string.format(L["Guild goal: %s / %s %s"], ns.FormatValue(gmetric, cur, false),
			ns.FormatValue(gmetric, target, false), gmetric.short))
		controls.goalPct = math.min(1, cur / target)
		items[#items + 1] = controls.goalBox
	end
	for _, box in ipairs({ controls.awardBox, controls.challengeBox, controls.goalBox }) do box:Hide() end
	local function place(box, x, y, width)
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", x, y)
		box:SetWidth(width)
		box.text:SetWidth(width - 10)
		if box == controls.goalBox then controls.goalFill:SetWidth(math.max(1, (width - 8) * (controls.goalPct or 0))) end
		box:Show()
	end
	local n, half = #items, 275
	if n == 1 then
		place(items[1], 18, -4, 556)
	elseif n == 2 then
		place(items[1], 18, -4, half); place(items[2], 299, -4, half)
	elseif n == 3 then
		place(items[1], 18, -4, 556); place(items[2], 18, -30, half); place(items[3], 299, -30, half)
	end
	local rowsUsed = (n == 0) and 0 or (n == 3 and 2 or 1)
	return rowsUsed * 26
end

local function RefreshChips(g)
	local v = ns.db.view
	for key, chip in pairs(controls.chips) do chip:SetSelected(v.metric == key) end
	local inChips = false
	for _, key in ipairs(CHIPS) do if key == v.metric then inChips = true end end
	if controls.more.Refresh then controls.more:Refresh() end
	if not inChips and controls.more.SetText and not controls.more.SetupMenu then
		local m = ns.METRIC_BY_KEY[v.metric]
		controls.more:SetText(m and m.short or L["More rankings"])
	end
end

local function RefreshList(g)
	local v = ns.db.view
	if v.metric == "playtime" and g.rules.showPlaytime == false then v.metric = "score" end
	local stripH = LayoutStrip(g)
	controls.body:ClearAllPoints()
	controls.body:SetPoint("TOPLEFT", 0, -(4 + stripH))
	controls.body:SetPoint("BOTTOMRIGHT", 0, 0)

	local data, unranked, metric, useRate = ns.BuildBoard(g, v.metric, v.period, v.perHour, v.bracket)
	local changes = ns.RankChanges(g, data, metric.key, v.period, v.perHour, v.bracket)
	local hasChanges = next(changes) ~= nil
	RefreshChips(g)
	controls.desc:SetText(ns.PeriodDescription(v.period, g))
	valueHeader:SetText(metric.key == "score" and L["Score"] or ((useRate and metric.short .. "/h") or metric.short))
	changeHeader:SetShown(hasChanges)
	if metric.rate then controls.perHour:Enable() else controls.perHour:Disable() end
	controls.perHour:SetChecked(v.perHour)
	resetText:SetText(ns.ResetDescription(g))
	local showPlayed = g.rules.showPlaytime ~= false
	controls.playedHeader:SetShown(showPlayed)

	local top = data[1] and data[1].value or 0
	local selected = ns.Card and ns.Card.key
	local rosterKnown = UI.RosterKnown(g)
	if rosterKnown then controls.onlineOnly:Enable() else controls.onlineOnly:Disable() end
	controls.onlineOnly:SetChecked(v.onlineOnly and true or false)
	-- "Online only" hides offline members but keeps everyone's real rank number
	local shown = {}
	for i, d in ipairs(data) do
		if not (v.onlineOnly and rosterKnown and not UI.IsOnline(g, d.key)) then shown[#shown + 1] = { rank = i, d = d } end
	end
	for i, item in ipairs(shown) do
		local d, rank = item.d, item.rank
		local r = GetRow(i)
		r.data = d
		r.rank:SetText((RANK_COLORS[rank] or "|cffffffff") .. rank .. ".|r")
		local online = UI.IsOnline(g, d.key)
		local icon = (online == true and ONLINE_ICON) or (online == false and OFFLINE_ICON) or ""
		r.name:SetText(icon .. ClassColored(d.name, d.class) .. ns.Hall.Badge(g, d.key))
		r.level:SetText(d.level or "?")
		r.value:SetText(ns.FormatValue(metric, d.value, useRate))
		local frac
		if metric.key == "score" then
			frac = (d.value or 0) / 100
		elseif not metric.lowerIsBetter and top > 0 then
			frac = (d.value or 0) / top
		end
		r.barBg:SetShown(frac ~= nil)
		r.bar:SetShown(frac ~= nil and frac > 0)
		if frac then r.bar:SetWidth(math.max(1, BAR_W * math.min(1, frac))) end
		r.change:SetText(hasChanges and ChangeText(changes[d.key]) or "")
		if not showPlayed then
			r.played:SetText("")
		elseif ns.PlaytimeShownFor(g, d.key) then
			r.played:SetText(ns.FormatTime(d.playtime))
		else
			r.played:SetText("|cff808080" .. L["hidden"] .. "|r")
		end
		if selected == d.key then
			r.bg:SetColorTexture(1, 0.82, 0, 0.16)
		elseif d.key == ns.me then
			r.bg:SetColorTexture(0.2, 0.8, 0.4, 0.18)
		else
			r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
		end
		r:Show()
	end
	for i = #shown + 1, #rows do
		rows[i].data = nil
		rows[i]:Hide()
	end
	content:SetHeight(math.max(1, #shown * ROW_H))

	if #data > 0 and #shown == 0 then
		emptyText:SetText(L["Nobody on this list is online right now."] .. "\n" .. L["Untick 'Online only' to see everyone."])
		emptyText:Show()
		controls.emptyInvite:Hide()
	elseif #data == 0 then
		local needsTime = useRate or metric.lowerIsBetter or metric.key == "score"
		local head = metric.key == "score" and L["Nobody's ranked yet for this period."]
			or string.format(L["Nobody has any %s yet for this period."], metric.short)
		emptyText:SetText(head .. "\n" .. (needsTime
			and string.format(L["Members show up after %d min of play, once they have Guild Ranks."], g.rules.minMinutes)
			or L["Members show up once they have Guild Ranks."]))
		emptyText:Show()
		controls.emptyInvite:SetShown(not g.solo and not g.demo)
	else
		emptyText:Hide()
		controls.emptyInvite:Hide()
	end

	local parts = {}
	local with, total = UI.AddonUsers(g)
	if g.solo then
		parts[#parts + 1] = L["Not in a guild"]
	elseif g.demo then
		parts[#parts + 1] = L["Sample data"]
	elseif with then
		parts[#parts + 1] = string.format(L["%d of %d members use Guild Ranks"], with, total)
	elseif g ~= ns.G() then
		parts[#parts + 1] = L["(one of your other characters' guilds)"]
	end
	local online = UI.OnlineCount(g)
	if online then parts[#parts + 1] = ONLINE_ICON .. string.format(L["%d online"], online) end
	if unranked > 0 then parts[#parts + 1] = string.format(L["%d under %d min (not ranked)"], unranked, g.rules.minMinutes) end
	if not g.solo and not g.demo then parts[#parts + 1] = L["updated"] .. " " .. ns.FormatAgo(ns.Comm.lastReceived) end
	footerText:SetText(table.concat(parts, "  ·  "))
end

---------------------------------------------------------------------------
-- Members view (roster: who has the addon, versions, exclusions)
---------------------------------------------------------------------------
local function GetMemberRow(i)
	if memberRows[i] then return memberRows[i] end
	local r = CreateFrame("Frame", nil, w.membersContent)
	r:SetSize(530, ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
	r.name = FS(r, "GameFontHighlight"); r.name:SetPoint("LEFT", 4, 0); r.name:SetWidth(170)
	r.level = FS(r, "GameFontHighlight", "CENTER"); r.level:SetPoint("LEFT", 176, 0); r.level:SetWidth(36)
	r.rank = FS(r, "GameFontHighlightSmall"); r.rank:SetPoint("LEFT", 218, 0); r.rank:SetWidth(120)
	r.addon = FS(r, "GameFontHighlightSmall"); r.addon:SetPoint("LEFT", 342, 0); r.addon:SetWidth(100)
	r.toggle = MakeButton(r, L["Exclude"], 80, function(self)
		local g = ns.G()
		local key = self:GetParent().key
		if not g or not key or not ns.CanEditRules(g) then return end
		g.rules.excluded[key] = (not g.rules.excluded[key]) or nil
		ns.Comm.PublishRules()
		UI.Refresh()
	end)
	r.toggle:SetPoint("RIGHT", -4, 0)
	r.toggle:SetHeight(18)
	memberRows[i] = r
	return r
end

-- Officers see the invite nudge while some members don't have the addon, until "Not now" (or Invite) this week
function UI.ShouldNudge(g, withAddon, total)
	if not g or g.solo or g ~= ns.G() or not ns.rosterReady or not ns.CanEditRules(g) then return false end
	if not withAddon or not total or total < 2 or withAddon >= total then return false end
	return g.nudgeWeek ~= ns.WeekStart(g)
end
function UI.NudgeText() return w.nudge and w.nudge:IsShown() and w.nudge.text:GetText() or nil end -- for the automated tests
function UI.NudgeClick(which) local b = w.nudge and w.nudge[which]; if b then b:GetScript("OnClick")(b) end end -- for the automated tests

local function RefreshMembers(g)
	local list = {}
	local useRoster = g == ns.G() and not g.solo and ns.rosterReady
	if useRoster then
		for key, info in pairs(ns.roster) do
			list[#list + 1] = { key = key, level = info.level or 0, class = info.class, rank = info.rankName or "", rankIndex = info.rankIndex or 99 }
		end
	else
		for key, p in pairs(g.players) do
			list[#list + 1] = { key = key, level = p.level or 0, class = p.class, rank = "", rankIndex = 99 }
		end
	end
	table.sort(list, function(a, b)
		local ha, hb = g.players[a.key] ~= nil, g.players[b.key] ~= nil
		if ha ~= hb then return ha end
		if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
		return a.key < b.key
	end)

	local withAddon, canEdit = 0, ns.CanEditRules(g) and not g.solo
	for i, m in ipairs(list) do
		local r = GetMemberRow(i)
		r.key = m.key
		local p = g.players[m.key]
		local excluded = g.rules.excluded[m.key]
		r.name:SetText(ClassColored(ns.ShortName(m.key), m.class) .. (excluded and (" |cffff6060(" .. L["excluded"] .. ")|r") or ""))
		r.level:SetText(m.level > 0 and m.level or "")
		r.rank:SetText(m.rank)
		if g.hidden[m.key] then
			r.addon:SetText("|cff999999" .. L["not sharing"] .. "|r")
		elseif p then
			withAddon = withAddon + 1
			r.addon:SetText("|cff60ff60" .. (p.version or L["yes"]) .. "|r")
		else
			r.addon:SetText("|cff999999-|r")
		end
		r.toggle:SetText(excluded and L["Include"] or L["Exclude"])
		r.toggle:SetShown(canEdit and p ~= nil)
		r:Show()
	end
	for i = #list + 1, #memberRows do memberRows[i]:Hide() end
	w.membersContent:SetHeight(math.max(1, #list * ROW_H))

	local showNudge = UI.ShouldNudge(g, withAddon, #list)
	w.nudge:SetShown(showNudge)
	if showNudge then
		w.nudge.text:SetText("|cffffd100" .. string.format(L["%d of %d members use Guild Ranks."], withAddon, #list) .. "|r  |cffa0a0a0"
			.. string.format(L["The other %d aren't on the leaderboards yet."], #list - withAddon) .. "|r")
	end
	w.membersInner:ClearAllPoints()
	w.membersInner:SetPoint("TOPLEFT", 0, showNudge and -36 or 0)
	w.membersInner:SetPoint("BOTTOMRIGHT")
	subtitle:SetText(useRoster
		and string.format(L["%d members  ·  %d use Guild Ranks  ·  invite the rest to join in!"], #list, withAddon)
		or L["Roster is only available for your current guild"])
	footerText:SetText(canEdit and L["Officers: use Exclude to remove someone (e.g. a cheater) from the rankings."] or "")
end

---------------------------------------------------------------------------
-- Settings view: "You" and "Guild rules"
---------------------------------------------------------------------------
local function LoadPending(g)
	local r = g.rules
	local pend = { resetDay = r.resetDay, resetHour = r.resetHour or 0, showPlaytime = r.showPlaytime ~= false,
		minMinutes = r.minMinutes, managerRank = r.managerRank,
		showSpoon = r.showSpoon, itemValue = r.itemValue, announceMVP = r.announceMVP,
		challengeMetric = r.challengeMetric or "", challengePrize = r.challengePrize or "",
		goalMetric = r.goalMetric or "", goalTarget = r.goalTarget or 0, gold = {} }
	for _, src in ipairs(ns.GOLD_SOURCES) do pend.gold[src] = r.gold[src] end
	w.pending, w.pendingFor = pend, g
end

local function GoalIsMoney(metricKey)
	local m = ns.METRIC_BY_KEY[metricKey or ""]
	return m and m.fmt == "money"
end

-- Has the officer changed anything since the rules were loaded?
local function PendingChanged(g)
	local pend, r = w.pending, g.rules
	if not pend then return false end
	local same = pend.resetDay == r.resetDay and (pend.resetHour or 0) == (r.resetHour or 0)
		and (pend.showPlaytime ~= false) == (r.showPlaytime ~= false)
		and math.floor(pend.minMinutes or 0) == (r.minMinutes or 0)
		and (pend.showSpoon and true or false) == (r.showSpoon and true or false)
		and (pend.announceMVP and true or false) == (r.announceMVP and true or false)
		and pend.itemValue == r.itemValue
		and (pend.challengeMetric or "") == (r.challengeMetric or "")
		and (pend.challengePrize or "") == (r.challengePrize or "")
		and (pend.goalMetric or "") == (r.goalMetric or "")
		and ((pend.goalMetric or "") == "" or math.floor(pend.goalTarget or 0) == (r.goalTarget or 0))
		and pend.managerRank == r.managerRank
	for _, src in ipairs(ns.GOLD_SOURCES) do
		if (pend.gold[src] and true or false) ~= (r.gold[src] and true or false) then same = false end
	end
	return not same
end

local function UpdateUnsaved()
	local g = w.pendingFor
	if not g or not w.unsaved then return end
	local changed = PendingChanged(g)
	w.unsaved:SetShown(changed)
	if changed then w.discard:Enable() else w.discard:Disable() end
end

-- Plain-language summary of the guild's rules (what members see)
function UI.RulesSummary(g)
	local r, lines = g.rules, {}
	local function add(label, value) lines[#lines + 1] = "|cffb0aa98" .. label .. ":|r  " .. value end
	add(L["Week resets"], string.format(L["%s %02d:00 realm time"], ns.WEEKDAYS[r.resetDay] or "?", r.resetHour or 0))
	add(L["Ranked from"], string.format(L["%d min played"], r.minMinutes or 0))
	local SHORT = { loot = L["loot"], quest = L["quest rewards"], vendor = L["vendor sales"], ah = L["Auction House"],
		mail = L["mail"], trade = L["trades"], other = L["other"] }
	local off = {}
	for _, src in ipairs(ns.GOLD_SOURCES) do
		if not r.gold[src] then off[#off + 1] = SHORT[src] end
	end
	local list = #off > 1 and (table.concat(off, ", ", 1, #off - 1) .. " " .. L["and"] .. " " .. off[#off]) or off[1]
	add(L["Gold counted"], #off == 0 and L["all sources"] or (L["all sources except"] .. " " .. list))
	add(L["Loot value"], r.itemValue == "auction" and L["auction price"] or L["vendor price"])
	add(L["Wooden spoon"], r.showSpoon and L["shown"] or L["off"])
	add(L["Play time"], r.showPlaytime == false and L["hidden for everyone"] or L["shown (members can hide their own)"])
	add(L["MVP in guild chat"], r.announceMVP and L["on"] or L["off"])
	local cm = ns.METRIC_BY_KEY[r.challengeMetric or ""]
	add(L["Weekly challenge"], cm and (cm.short .. "/h" .. (r.challengePrize and ("  ·  " .. L["prize"] .. " " .. r.challengePrize) or "")) or L["none"])
	local gm = ns.METRIC_BY_KEY[r.goalMetric or ""]
	add(L["Guild goal"], (gm and (r.goalTarget or 0) > 0) and (ns.FormatValue(gm, r.goalTarget, false) .. " " .. gm.short) or L["none"])
	local who
	for _, o in ipairs(ns.RankChoices()) do if o.value == (r.managerRank or 1) then who = o.text end end
	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cff808080" .. (r.by and string.format(L["Set by %s on %s"], r.by, date("%d %b", r.version)) or L["Using default rules"])
		.. "  ·  " .. string.format(L["can be changed by: %s"], who or "?") .. "|r"
	return table.concat(lines, "\n")
end

local function SetSettingsTab(which)
	w.settingsTab = which
	w.youTab:SetSelected(which == "you")
	w.rulesTab:SetSelected(which == "rules")
	w.youPane:SetShown(which == "you")
	w.rulesPane:SetShown(which == "rules")
end

local function RefreshSettings(g)
	if w.pendingFor ~= g then LoadPending(g) end
	local pend = w.pending
	local can = ns.CanEditRules(g) and not g.demo
	local isGM = g.solo or (g == ns.G() and ns.IsGuildMaster())
	subtitle:SetText(L["Settings"] .. "  ·  " .. g.name)
	SetSettingsTab(w.settingsTab or "you")

	-- You
	w.share:SetChecked(ns.db.share)
	w.showPlay:SetChecked(ns.db.showPlay ~= false)
	w.bar:SetChecked(ns.db.ui.bar.show)
	w.alerts:SetChecked(ns.db.alerts)
	w.popup:SetChecked(ns.db.weeklyPopup)
	w.announceLevel:SetChecked(ns.db.announceLevel)
	w.leadCards:SetChecked(ns.db.leadCards ~= false)
	local price = ns.PriceSourceName()
	w.status:SetText(string.format(
		L["Addon version: %s%s\nDamage meter: %s\nAuction prices from: %s\nMessages waiting to send: %d%s"],
		ns.VERSION, ns.newerVersion and (" |cffffcc00(" .. string.format(L["%s available"], ns.newerVersion) .. ")|r") or "",
		ns.Tracker.state.meterStatus, price or L["none (install TradeSkillMaster or Auctionator)"],
		ns.Comm.QueueLength(), IsInInstance() and ("  (" .. L["paused inside instances"] .. ")") or ""))

	-- Guild rules: editor for those who may change them, a summary for everyone else
	w.editor:SetShown(can)
	w.summary:SetShown(not can)
	if not can then
		w.summaryHead:SetText(g.demo and L["Sample data: rules can't be changed here."]
			or L["Only the Guild Master and chosen ranks can change these rules."])
		w.summaryText:SetText(UI.RulesSummary(g))
	else
		w.info:SetText(g.solo and L["You're not in a guild: rankings only include your own characters."]
			or L["You can change these rules. Saving shares them with the whole guild."])
		w.by:SetText(g.rules.by and string.format(L["Last set by %s on %s"], g.rules.by, date("%d %b %H:%M", g.rules.version)) or L["Using default rules"])
		if not w.minBox:HasFocus() then w.minBox:SetText(tostring(pend.minMinutes)) end
		if not w.prizeBox:HasFocus() then w.prizeBox:SetText(pend.challengePrize or "") end
		if not w.goalBox:HasFocus() then
			local target = pend.goalTarget or 0
			w.goalBox:SetText(target > 0 and tostring(GoalIsMoney(pend.goalMetric) and math.floor(target / 10000) or target) or "")
		end
		w.goalUnit:SetText(GoalIsMoney(pend.goalMetric) and L["gold"] or "")
		if isGM and not g.solo then w.manager:Enable() else w.manager:Disable() end
		w.showPlaytime:SetChecked(pend.showPlaytime)
		w.spoon:SetChecked(pend.showSpoon)
		w.announceMVP:SetChecked(pend.announceMVP)
		for src, cb in pairs(w.gold) do cb:SetChecked(pend.gold[src]) end
		UpdateUnsaved()
	end
	footerText:SetText("")
end

local function BuildSettings()
	local v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", 0, -88)
	v:SetPoint("BOTTOMRIGHT", 0, 56)
	v:Hide()
	views.settings = v

	w.youTab = MakeTab(v, L["You"], 70, function() SetSettingsTab("you") end, true)
	w.youTab:SetPoint("TOPLEFT", 18, 0)
	w.rulesTab = MakeTab(v, L["Guild rules"], 100, function() SetSettingsTab("rules") end, true)
	w.rulesTab:SetPoint("LEFT", w.youTab, "RIGHT", 4, 0)
	local line = v:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 16, -21); line:SetPoint("TOPRIGHT", -16, -21); line:SetHeight(1)
	line:SetColorTexture(0.35, 0.3, 0.2, 0.8)

	-- You
	local you = CreateFrame("Frame", nil, v)
	you:SetPoint("TOPLEFT", 0, -28); you:SetPoint("BOTTOMRIGHT")
	w.youPane = you
	local function check(key, label, tip, y, onClick)
		w[key] = MakeCheck(you, label, onClick, tip)
		w[key]:SetPoint("TOPLEFT", 20, y)
	end
	check("share", L["Share my stats with my guild"], L["Off: guildmates stop seeing your stats and you leave their rankings."], -4,
		function(on) ns.Comm.SetShare(on) end)
	check("showPlay", L["Show my play time to my guild"], L["Off: others see 'hidden'. Per-hour rankings still use it."], -28,
		function(on) ns.Comm.SetShowPlay(on) end)
	check("bar", L["Show session bar"], L["A small movable bar with your rank and this session's gold and XP per hour."], -52,
		function(on) ns.Bar.SetShown(on) end)
	check("alerts", L["Rank-change alerts"], L["A short message when a guildmate passes you in a ranking."], -76,
		function(on) ns.db.alerts = on end)
	check("popup", L["Weekly results popup"], L["After the weekly reset, a popup shows how you did."], -100,
		function(on) ns.db.weeklyPopup = on end)
	check("announceLevel", L["Announce my level-ups in guild chat"], nil, -124,
		function(on) ns.db.announceLevel = on end)
	check("leadCards", L["Lead cards (you take or lose #1)"], L["An achievement-style card, with a sound, when you become #1 in a ranking this week, and a smaller one when someone takes it from you."], -148,
		function(on) ns.db.leadCards = on end)
	Label(you, L["About"], 22, -186, "GameFontNormal")
	w.status = FS(you, "GameFontHighlightSmall")
	w.status:SetWordWrap(true)
	w.status:SetWidth(540)
	w.status:SetSpacing(2)
	w.status:SetPoint("TOPLEFT", 22, -204)
	local welcome = MakeButton(you, L["Show the welcome again"], 180, function() if ns.Welcome then ns.Welcome.Show(true) end end)
	welcome:SetPoint("TOPLEFT", 20, -274)

	-- Guild rules
	local rules = CreateFrame("Frame", nil, v)
	rules:SetPoint("TOPLEFT", 0, -28); rules:SetPoint("BOTTOMRIGHT")
	w.rulesPane = rules

	local summary = CreateFrame("Frame", nil, rules)
	summary:SetAllPoints()
	w.summary = summary
	w.summaryHead = FS(summary, "GameFontHighlightSmall"); w.summaryHead:SetPoint("TOPLEFT", 22, -6)
	w.summaryText = FS(summary, "GameFontHighlight")
	w.summaryText:SetWordWrap(true); w.summaryText:SetWidth(540); w.summaryText:SetSpacing(4)
	w.summaryText:SetPoint("TOPLEFT", 22, -28)

	local ed = CreateFrame("Frame", nil, rules)
	ed:SetAllPoints()
	w.editor = ed
	local function set(field) return function(val) w.pending[field] = val; UpdateUnsaved() end end
	w.info = FS(ed, "GameFontHighlightSmall"); w.info:SetPoint("TOPLEFT", 22, -4)
	w.by = FS(ed, "GameFontDisableSmall"); w.by:SetPoint("TOPLEFT", 22, -18)

	Label(ed, L["Weekly reset (realm time)"], 22, -38)
	w.reset = MakeDropdown(ed, 100, function()
		local o = {}
		for i, name in ipairs(ns.WEEKDAYS) do o[#o + 1] = { value = i, text = name } end
		return o
	end, function() return w.pending and w.pending.resetDay end, set("resetDay"))
	w.reset:SetPoint("TOPLEFT", 20, -52)
	Tip(w.reset, L["Weekly reset"], L["When the week (and the weekly MVP) starts, in realm time."])
	w.resetHour = MakeDropdown(ed, 70, function()
		local o = {}
		for h = 0, 23 do o[#o + 1] = { value = h, text = string.format("%02d:00", h) } end
		return o
	end, function() return w.pending and w.pending.resetHour end, set("resetHour"))
	w.resetHour:SetPoint("TOPLEFT", 126, -52)

	Label(ed, L["Min. play time (min)"], 206, -38)
	w.minBox = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
	w.minBox:SetSize(60, 22)
	w.minBox:SetPoint("TOPLEFT", 212, -52)
	w.minBox:SetAutoFocus(false)
	w.minBox:SetNumeric(true)
	w.minBox:SetMaxLetters(4)
	local function readMin(self) w.pending.minMinutes = tonumber(self:GetText()) or w.pending.minMinutes; UpdateUnsaved() end
	w.minBox:SetScript("OnEnterPressed", function(self) readMin(self); self:ClearFocus() end)
	w.minBox:SetScript("OnEditFocusLost", readMin)
	w.minBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	Tip(w.minBox, L["Minimum play time"], L["Members need this much play time in a period to be ranked, so a lucky 5 minutes can't top the per-hour boards."])

	Label(ed, L["Who can change rules (Guild Master only)"], 322, -38)
	w.manager = MakeDropdown(ed, 210, ns.RankChoices, function() return w.pending and w.pending.managerRank end, set("managerRank"))
	w.manager:SetPoint("TOPLEFT", 320, -52)

	Label(ed, L["Loot value uses"], 22, -84)
	w.itemValue = MakeDropdown(ed, 250, function()
		return {
			{ value = "vendor", text = L["Vendor price (fair for everyone)"] },
			{ value = "auction", text = L["Auction price (TSM / Auctionator)"] },
		}
	end, function() return w.pending and w.pending.itemValue end, set("itemValue"))
	w.itemValue:SetPoint("TOPLEFT", 20, -98)
	w.spoon = MakeCheck(ed, L["Show the Wooden spoon (last place)"], function(on) w.pending.showSpoon = on; UpdateUnsaved() end,
		L["A light-hearted award for the lowest Guild score of the week."])
	w.spoon:SetPoint("TOPLEFT", 300, -80)
	w.announceMVP = MakeCheck(ed, L["Post last week's MVP in guild chat"], function(on) w.pending.announceMVP = on; UpdateUnsaved() end,
		L["Posted once per week, by the first member online after the reset."])
	w.announceMVP:SetPoint("TOPLEFT", 300, -102)
	w.showPlaytime = MakeCheck(ed, L["Show play time (column and ranking)"], function(on) w.pending.showPlaytime = on; UpdateUnsaved() end,
		L["Off: play time is hidden for everyone. Per-hour rankings still use it."])
	w.showPlaytime:SetPoint("TOPLEFT", 300, -124)

	Label(ed, L["Count gold from"], 22, -150)
	w.gold = {}
	for i, src in ipairs(ns.GOLD_SOURCES) do
		local cb = MakeCheck(ed, ns.GOLD_SOURCE_LABELS[src], function(on) w.pending.gold[src] = on; UpdateUnsaved() end)
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		cb:SetPoint("TOPLEFT", 20 + col * 180, -164 - row * 24)
		w.gold[src] = cb
	end
	Tip(w.gold.mail, L["Mail (not AH)"], L["Off by default: gold mailed from alts or friends would count as earned."])
	Tip(w.gold.ah, L["Auction House"], L["Off by default: sales happen while you're offline but are collected in seconds, which makes Gold/h jump."])

	Label(ed, L["Weekly challenge"], 22, -240)
	w.challenge = MakeDropdown(ed, 200, ns.ChallengeChoices, function() return w.pending and w.pending.challengeMetric end, set("challengeMetric"))
	w.challenge:SetPoint("TOPLEFT", 20, -254)
	Tip(w.challenge, L["Weekly challenge"], L["One featured ranking for the week, with an optional prize."])
	Label(ed, L["Prize (optional)"], 236, -240)
	w.prizeBox = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
	w.prizeBox:SetSize(200, 22)
	w.prizeBox:SetPoint("TOPLEFT", 242, -254)
	w.prizeBox:SetAutoFocus(false)
	w.prizeBox:SetMaxLetters(40)
	local function readPrize(self) w.pending.challengePrize = ns.CleanText(self:GetText(), 40); UpdateUnsaved() end
	w.prizeBox:SetScript("OnEnterPressed", function(self) readPrize(self); self:ClearFocus() end)
	w.prizeBox:SetScript("OnEditFocusLost", readPrize)
	w.prizeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	Label(ed, L["Guild goal (combined this week)"], 22, -286)
	w.goal = MakeDropdown(ed, 200, ns.GoalChoices, function() return w.pending and w.pending.goalMetric end,
		function(val) w.pending.goalMetric = val; UpdateUnsaved(); UI.Refresh() end)
	w.goal:SetPoint("TOPLEFT", 20, -300)
	Tip(w.goal, L["Guild goal"], L["A target the whole guild works towards together this week."])
	Label(ed, L["Target"], 236, -286)
	w.goalBox = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
	w.goalBox:SetSize(100, 22)
	w.goalBox:SetPoint("TOPLEFT", 242, -300)
	w.goalBox:SetAutoFocus(false)
	w.goalBox:SetNumeric(true)
	w.goalBox:SetMaxLetters(9)
	local function readGoal(self)
		local n = tonumber(self:GetText()) or 0
		w.pending.goalTarget = GoalIsMoney(w.pending.goalMetric) and n * 10000 or n
		UpdateUnsaved()
	end
	w.goalBox:SetScript("OnEnterPressed", function(self) readGoal(self); self:ClearFocus() end)
	w.goalBox:SetScript("OnEditFocusLost", readGoal)
	w.goalBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	w.goalUnit = FS(ed, "GameFontHighlightSmall"); w.goalUnit:SetPoint("LEFT", w.goalBox, "RIGHT", 6, 0)

	-- Save bar
	local sep = ed:CreateTexture(nil, "ARTWORK")
	sep:SetPoint("TOPLEFT", 16, -340); sep:SetPoint("TOPRIGHT", -16, -340); sep:SetHeight(1)
	sep:SetColorTexture(0.35, 0.3, 0.2, 0.8)
	w.unsaved = FS(ed, "GameFontNormal")
	w.unsaved:SetPoint("TOPLEFT", 22, -354)
	w.unsaved:SetText("|cffffcc00" .. L["Unsaved changes"] .. "|r")
	w.save = MakeButton(ed, L["Save and share"], 170, function()
		local g = ns.V()
		if g.demo then return end
		local pend, r = w.pending, g.rules
		r.resetDay = pend.resetDay
		if (pend.resetHour or 0) ~= (r.resetHour or 0) then
			r.resetHour = pend.resetHour or 0
			ns.InvalidateToday()
		end
		r.showPlaytime = pend.showPlaytime ~= false
		r.minMinutes = math.max(0, math.floor(pend.minMinutes or 0))
		r.showSpoon = pend.showSpoon and true or false
		r.announceMVP = pend.announceMVP and true or false
		r.itemValue = pend.itemValue
		r.challengeMetric = (pend.challengeMetric ~= "" and pend.challengeMetric) or nil
		r.challengePrize = (pend.challengePrize ~= "" and pend.challengePrize) or nil
		r.goalMetric = (pend.goalMetric ~= "" and pend.goalMetric) or nil
		r.goalTarget = r.goalMetric and math.max(0, math.floor(pend.goalTarget or 0)) or 0
		if g.solo or ns.IsGuildMaster() then r.managerRank = pend.managerRank end
		for _, src in ipairs(ns.GOLD_SOURCES) do r.gold[src] = pend.gold[src] and true or false end
		ns.Comm.PublishRules()
		ns.Print(g.solo and L["Rules saved."] or L["Rules saved and shared with the guild."])
		LoadPending(g)
		UI.Refresh()
	end)
	w.save:SetPoint("TOPRIGHT", -20, -348)
	w.discard = MakeButton(ed, L["Discard"], 90, function()
		w.pendingFor = nil
		UI.Refresh()
		for _, dd in ipairs({ w.reset, w.resetHour, w.itemValue, w.manager, w.challenge, w.goal }) do dd:Refresh() end
	end)
	w.discard:SetPoint("RIGHT", w.save, "LEFT", -6, 0)
end

---------------------------------------------------------------------------
-- Hall of Fame view
---------------------------------------------------------------------------
local function RefreshHall(g)
	ns.Hall.Update(g)
	local rec = ns.Hall.Records(g)
	local out = {}
	local function line(text) out[#out + 1] = text end
	local function name(key)
		local p = g.players[key]
		return ClassColored(ns.ShortName(key), p and p.class)
	end
	subtitle:SetText(L["Hall of Fame"] .. "  ·  " .. string.format(L["%d weeks recorded"], rec.weeks))
	if rec.weeks == 0 then
		line(L["No finished weeks yet. Records appear after the first weekly reset."])
	else
		line("|cffffd100" .. L["Most MVP awards"] .. "|r")
		for i = 1, math.min(5, #rec.mvps) do
			line(string.format("  %d. %s  |TInterface\\Icons\\INV_Misc_Trophy_Gold:12:12|t x%d", i, name(rec.mvps[i].key), rec.mvps[i].n))
		end
		line(" ")
		line("|cffffd100" .. L["Best week per ranking"] .. "|r")
		for _, b in ipairs(rec.best) do
			local m = ns.METRIC_BY_KEY[b.metric]
			local t = ns.KeyToTime(b.from)
			line(string.format("  %-14s %s  %s  |cff999999(%s)|r", m.short .. "/h", name(b.key), ns.FormatValue(m, b.value, true),
				t and date("%d %b", t) or b.from))
		end
		if #rec.streaks > 0 then
			line(" ")
			line("|cffffd100" .. L["Longest top-3 streaks"] .. "|r")
			for i = 1, math.min(5, #rec.streaks) do
				local st = rec.streaks[i]
				line(string.format(L["  %s: %d weeks%s"], name(st.key), st.n, st.current >= 2 and (" |cff40ff40(" .. L["ongoing"] .. ")|r") or ""))
			end
		end
		line(" ")
		line("|cffffd100" .. L["Weekly results"] .. "|r")
		for _, snap in ipairs(ns.Hall.Weeks(g)) do
			local t = ns.KeyToTime(snap.from)
			local text = string.format("  %s  %s %s", t and date("%d %b", t) or snap.from, L["MVP"], name(snap.mvp))
			if g.rules.showSpoon and snap.spoon then text = text .. "  ·  " .. L["Wooden spoon"] .. " " .. name(snap.spoon) end
			if snap.challenge then
				local m = ns.METRIC_BY_KEY[snap.challenge.metric]
				text = text .. "  ·  " .. string.format(L["challenge (%s) %s"], m and m.short or "?", name(snap.challenge.key))
			end
			line(text)
		end
	end
	w.hallText:SetText(table.concat(out, "\n"))
	w.hallContent:SetHeight(math.max(1, (w.hallText:GetStringHeight() or 400) + 10))
	footerText:SetText("")
end

---------------------------------------------------------------------------
-- Refresh + view switching
---------------------------------------------------------------------------
local function RefreshTitle(g)
	local guilds = 0
	for _ in pairs(ns.db.guilds) do guilds = guilds + 1 end
	local many = guilds > 1
	controls.guild:SetShown(many)
	guildText:SetShown(not many)
	if many and controls.guild.Refresh then controls.guild:Refresh() end
	guildText:SetText(g and ("|cffb9b4a8·  " .. (g.solo and L["No guild"] or g.name) .. "|r") or "")
end

function UI.Refresh()
	if not frame or not frame:IsShown() then return end
	local g = ns.V()
	RefreshTitle(g)
	if not g then
		subtitle:SetText(L["Loading your guild..."])
		return
	end
	subtitle:SetText("")
	resetText:SetText("")
	controls.invite:SetShown(not g.solo and not g.demo)
	if current == "settings" then
		RefreshSettings(g)
	elseif current == "members" then
		RefreshMembers(g)
	elseif current == "hall" then
		RefreshHall(g)
	elseif current == "me" then
		resetText:SetText(ns.ResetDescription(g))
		footerText:SetText(L["Your own stats, goals and bests. Only titles you choose to show are shared."])
		ns.MeView.Refresh(g)
	else
		RefreshList(g)
	end
	if ns.Card and ns.Card.Refresh then ns.Card.Refresh() end
	if ns.Welcome and ns.Welcome.IsShown() then ns.Welcome.Update() end
end

function UI.Show(view)
	if not ns.db then return end
	if not frame then CreateMain() end
	if not frame:IsShown() then frame:Show() end
	current = view or "list"
	for name, f in pairs(views) do f:SetShown(name == current) end
	for name, tab in pairs(tabs) do tab:SetSelected(name == current) end
	if current ~= "list" and ns.Card then ns.Card.Hide() end
	if current == "settings" then
		w.pendingFor = nil
		UI.Refresh()
		w.reset:Refresh(); w.resetHour:Refresh(); w.itemValue:Refresh(); w.manager:Refresh(); w.challenge:Refresh(); w.goal:Refresh()
	else
		UI.Refresh()
	end
	if ns.Welcome then
		if current == "list" then ns.Welcome.Show() else ns.Welcome.Hide() end
	end
end

local function GuildOptions()
	local o = {}
	for key, g in pairs(ns.db.guilds) do
		local label = g.solo and (L["No guild"] .. " (" .. (g.realm or "") .. ")") or (g.demo and g.name) or (g.name .. " - " .. (g.realm or ""))
		if key == ns.gkey then label = label .. " *" end
		o[#o + 1] = { value = key, text = label }
	end
	table.sort(o, function(a, b)
		if a.value == ns.gkey then return true end
		if b.value == ns.gkey then return false end
		return a.text < b.text
	end)
	return o
end

---------------------------------------------------------------------------
-- Build the window
---------------------------------------------------------------------------
local function BuildList()
	local v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", 0, -68)
	v:SetPoint("BOTTOMRIGHT", 0, 56)
	views.list = v

	local function Box(r, g, b)
		local box = CreateFrame("Frame", nil, v)
		box:SetSize(275, 22)
		local bg = box:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(r, g, b, 0.25)
		box.text = FS(box, "GameFontHighlightSmall", "LEFT")
		box.text:SetPoint("LEFT", 6, 0)
		box:Hide()
		return box.text, box
	end
	controls.award, controls.awardBox = Box(1, 0.75, 0.1)
	controls.challenge, controls.challengeBox = Box(0.2, 0.45, 0.9)
	controls.goal, controls.goalBox = Box(0.25, 0.25, 0.25)
	controls.goalFill = controls.goalBox:CreateTexture(nil, "BORDER")
	controls.goalFill:SetPoint("TOPLEFT", 4, -4)
	controls.goalFill:SetPoint("BOTTOMLEFT", 4, 4)
	controls.goalFill:SetWidth(1)
	controls.goalFill:SetColorTexture(0.2, 0.8, 0.3, 0.45)

	-- Everything below the award strip moves up or down with it
	local body = CreateFrame("Frame", nil, v)
	body:SetPoint("TOPLEFT", 0, -4)
	body:SetPoint("BOTTOMRIGHT")
	controls.body = body
	local view = ns.db.view

	-- One-click ranking chips + "More rankings"
	controls.chips = {}
	local x = 18
	for _, key in ipairs(CHIPS) do
		local m = ns.METRIC_BY_KEY[key]
		local chip = CreateFrame("Button", nil, body)
		chip:SetSize(CHIP_W[key], 20)
		chip:SetPoint("TOPLEFT", x, -2)
		chip.bg = chip:CreateTexture(nil, "BACKGROUND")
		chip.bg:SetAllPoints()
		chip.text = FS(chip, "GameFontHighlightSmall", "CENTER")
		chip.text:SetPoint("CENTER")
		chip.text:SetText(key == "score" and L["Score"] or m.short)
		local hl = chip:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		chip.SetSelected = function(self, on)
			if on then
				self.bg:SetColorTexture(0.45, 0.36, 0.08, 0.9)
				self.text:SetTextColor(1, 0.82, 0)
			else
				self.bg:SetColorTexture(0.16, 0.16, 0.18, 0.9)
				self.text:SetTextColor(0.85, 0.82, 0.75)
			end
		end
		chip:SetScript("OnClick", function() view.metric = key; UI.Refresh() end)
		Tip(chip, m.label)
		controls.chips[key] = chip
		x = x + CHIP_W[key] + 4
	end
	controls.more = MakeDropdown(body, 140, function()
		local o = {}
		for _, opt in ipairs(ns.RankingChoices(ns.V())) do
			local chip = false
			for _, key in ipairs(CHIPS) do if key == opt.value then chip = true end end
			if not chip then o[#o + 1] = opt end
		end
		return o
	end, function() return view.metric end, function(val) view.metric = val; UI.Refresh() end, L["More rankings"])
	controls.more:SetPoint("TOPLEFT", x + 2, 0)
	controls.perHour = MakeCheck(body, L["Per hour"], function(checked) view.perHour = checked; UI.Refresh() end,
		L["Per hour of play (fair for everyone) or totals."])
	controls.perHour:SetPoint("TOPLEFT", 482, -1)

	controls.period = MakeDropdown(body, 120, function()
		local o = {}
		for _, p in ipairs(ns.PERIODS) do o[#o + 1] = { value = p.key, text = p.label } end
		return o
	end, function() return view.period end, function(val) view.period = val; UI.Refresh() end)
	controls.period:SetPoint("TOPLEFT", 18, -28)
	controls.bracket = MakeDropdown(body, 100, ns.Brackets, function() return view.bracket end,
		function(val) view.bracket = val; UI.Refresh() end)
	controls.bracket:SetPoint("TOPLEFT", 144, -28)
	controls.desc = FS(body, "GameFontDisableSmall")
	controls.desc:SetPoint("TOPLEFT", 254, -34)
	controls.desc:SetWidth(222)
	controls.onlineOnly = MakeCheck(body, L["Online only"], function(checked) view.onlineOnly = checked; UI.Refresh() end,
		L["Show only guildmates who are online right now (their rank numbers stay the same)."])
	controls.onlineOnly:SetPoint("TOPLEFT", 482, -27)

	local hdr = CreateFrame("Frame", nil, body)
	hdr:SetPoint("TOPLEFT", 18, -58)
	hdr:SetSize(530, 18)
	local h1 = FS(hdr, "GameFontNormalSmall", "RIGHT"); h1:SetPoint("LEFT", 0, 0); h1:SetWidth(28); h1:SetText("#")
	local h2 = FS(hdr, "GameFontNormalSmall"); h2:SetPoint("LEFT", 36, 0); h2:SetText(L["Name"])
	local h3 = FS(hdr, "GameFontNormalSmall", "CENTER"); h3:SetPoint("LEFT", 240, 0); h3:SetWidth(32); h3:SetText(L["Lvl"])
	valueHeader = FS(hdr, "GameFontNormalSmall", "RIGHT"); valueHeader:SetPoint("LEFT", 282, 0); valueHeader:SetWidth(158)
	changeHeader = CreateFrame("Frame", nil, hdr)
	changeHeader:SetPoint("LEFT", 444, 0); changeHeader:SetSize(34, 18)
	local ch = FS(changeHeader, "GameFontNormalSmall", "RIGHT"); ch:SetAllPoints(); ch:SetText("+/-")
	changeHeader:EnableMouse(true)
	Tip(changeHeader, L["Rank change"], L["Places moved since the same point in the previous period (last week, yesterday, last month)."])
	local h5 = FS(hdr, "GameFontNormalSmall", "RIGHT"); h5:SetPoint("LEFT", 482, 0); h5:SetWidth(48); h5:SetText(L["Played"])
	controls.playedHeader = h5

	local _, child = MakeScroll(body, -78)
	content = child
	emptyText = FS(body, "GameFontDisable", "CENTER")
	emptyText:SetWordWrap(true)
	emptyText:SetPoint("TOP", 0, -140)
	emptyText:SetWidth(460)
	controls.emptyInvite = MakeButton(body, L["Invite guildmates"], 150, function() if ns.Invite then ns.Invite.Show() end end)
	controls.emptyInvite:SetPoint("TOP", emptyText, "BOTTOM", 0, -12)
	controls.emptyInvite:Hide()
end

local function BuildMembers()
	local v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", 0, -88)
	v:SetPoint("BOTTOMRIGHT", 0, 56)
	v:Hide()
	views.members = v
	-- Officer nudge: "12 of 40 members use Guild Ranks", shown until dismissed for the week
	local nudge = CreateFrame("Frame", nil, v)
	nudge:SetPoint("TOPLEFT", 18, -2)
	nudge:SetSize(548, 30)
	local nbg = nudge:CreateTexture(nil, "BACKGROUND")
	nbg:SetAllPoints()
	nbg:SetColorTexture(0.17, 0.14, 0.05, 0.95)
	local nline = nudge:CreateTexture(nil, "BORDER")
	nline:SetPoint("BOTTOMLEFT"); nline:SetPoint("BOTTOMRIGHT"); nline:SetHeight(1)
	nline:SetColorTexture(0.54, 0.45, 0.19, 1)
	nudge.text = FS(nudge, "GameFontHighlightSmall")
	nudge.text:SetPoint("LEFT", 8, 0)
	nudge.text:SetWidth(370)
	nudge.text:SetWordWrap(true)
	local later = MakeButton(nudge, L["Not now"], 72, function()
		local g = ns.G()
		if g then g.nudgeWeek = ns.WeekStart(g) end
		UI.Refresh()
	end)
	later:SetPoint("RIGHT", -6, 0); later:SetHeight(20); nudge.later = later
	local inv = MakeButton(nudge, L["Invite"], 72, function()
		local g = ns.G()
		if g then g.nudgeWeek = ns.WeekStart(g) end
		if ns.Invite then ns.Invite.Show() end
		UI.Refresh()
	end)
	inv:SetPoint("RIGHT", later, "LEFT", -4, 0); inv:SetHeight(20); nudge.invite = inv
	w.nudge = nudge
	local inner = CreateFrame("Frame", nil, v)
	inner:SetPoint("TOPLEFT"); inner:SetPoint("BOTTOMRIGHT")
	w.membersInner = inner
	v = inner
	local hdr = CreateFrame("Frame", nil, v)
	hdr:SetPoint("TOPLEFT", 18, -4)
	hdr:SetSize(530, 18)
	local function H(text, x, width, justify)
		local f = FS(hdr, "GameFontNormalSmall", justify); f:SetPoint("LEFT", x, 0); f:SetWidth(width); f:SetText(text)
	end
	H(L["Name"], 4, 170)
	H(L["Lvl"], 176, 36, "CENTER")
	H(L["Rank"], 218, 120)
	H(L["Addon"], 342, 100)
	local _, child = MakeScroll(v, -24)
	w.membersContent = child
end

local function BuildHall()
	local v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", 0, -88)
	v:SetPoint("BOTTOMRIGHT", 0, 56)
	v:Hide()
	views.hall = v
	local _, child = MakeScroll(v, -4)
	w.hallContent = child
	w.hallText = FS(child, "GameFontHighlight")
	w.hallText:SetPoint("TOPLEFT", 4, -4)
	w.hallText:SetWidth(520)
	w.hallText:SetWordWrap(true)
	w.hallText:SetSpacing(3)
end

CreateMain = function()
	frame = CreateFrame("Frame", "GuildRanksFrame", UIParent, "BackdropTemplate")
	frame:SetSize(600, 660)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local p, _, rp, x, y = f:GetPoint()
		ns.db.ui.point = { p, rp, x, y }
	end)
	local pt = ns.db.ui.point
	if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("CENTER") end
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:Hide()
	tinsert(UISpecialFrames, "GuildRanksFrame")
	frame:SetScript("OnShow", function() ns.RequestRoster(); UI.Refresh() end)
	-- Keep online status fresh while the window is open
	C_Timer.NewTicker(30, function() if frame:IsShown() then ns.RequestRoster() end end)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- Title: "Guild Ranks · Froga" (a guild picker instead when your characters are in several guilds)
	titleText = FS(frame, "GameFontNormalLarge")
	titleText:SetPoint("TOPLEFT", 22, -18)
	titleText:SetText(L["Guild Ranks"])
	guildText = FS(frame, "GameFontHighlight")
	guildText:SetPoint("LEFT", titleText, "RIGHT", 6, 0)
	guildText:SetWidth(180)
	controls.guild = MakeDropdown(frame, 180, GuildOptions, function() return select(2, ns.V()) end, function(val)
		ns.db.view.guild = (val ~= ns.gkey) and val or nil
		w.pendingFor = nil
		if ns.Card then ns.Card.Hide() end
		UI.Refresh()
	end)
	controls.guild:SetPoint("LEFT", titleText, "RIGHT", 10, 0)
	controls.guild:Hide()
	resetText = FS(frame, "GameFontDisableSmall", "RIGHT")
	resetText:SetPoint("TOPRIGHT", -40, -22)
	resetText:SetWidth(225)

	-- Tabs
	local x = 16
	for _, t in ipairs({ { "list", L["Ranks"], 80 }, { "me", L["Me"], 56 }, { "hall", L["Hall of Fame"], 110 }, { "members", L["Members"], 90 }, { "settings", L["Settings"], 90 } }) do
		local view = t[1]
		local tab = MakeTab(frame, t[2], t[3], function() UI.Show(view) end)
		tab:SetPoint("TOPLEFT", x, -40)
		tabs[view] = tab
		x = x + t[3] + 4
	end
	local line = frame:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 14, -64); line:SetPoint("TOPRIGHT", -14, -64); line:SetHeight(1)
	line:SetColorTexture(0.35, 0.3, 0.2, 0.8)

	subtitle = FS(frame, "GameFontHighlightSmall", "CENTER")
	subtitle:SetPoint("TOP", 0, -72)
	subtitle:SetWidth(560)

	BuildList()
	BuildMembers()
	BuildSettings()
	BuildHall()
	views.me = ns.MeView.Build(frame)

	footerText = FS(frame, "GameFontDisableSmall")
	footerText:SetPoint("BOTTOMLEFT", 22, 42)
	footerText:SetWidth(556)

	local copy = MakeButton(frame, L["Copy for Discord"], 125, function()
		ns.ShowDiscordCopy(ns.V(), ns.db.view.period)
	end)
	copy:SetPoint("BOTTOMRIGHT", -20, 14)
	local sync = MakeButton(frame, L["Sync"], 70, function()
		ns.Comm.SyncNow()
		ns.Print(L["Asked the guild for fresh data."])
	end)
	sync:SetPoint("RIGHT", copy, "LEFT", -6, 0)
	Tip(sync, L["Sync"], L["Ask online guildmates for their latest data."])
	controls.invite = MakeButton(frame, L["Invite"], 80, function() if ns.Invite then ns.Invite.Show() end end)
	controls.invite:SetPoint("RIGHT", sync, "LEFT", -6, 0)
	Tip(controls.invite, L["Invite guildmates"], L["Post or copy a message telling guildmates how to install Guild Ranks."])
end

function UI.Toggle(view)
	if not ns.db then return end
	if not frame then CreateMain() end
	if frame:IsShown() and (not view or view == current) then
		frame:Hide()
	else
		frame:Show()
		UI.Show(view or current)
	end
end

---------------------------------------------------------------------------
-- Diagnostics (/granks diag)
---------------------------------------------------------------------------
function ns.Diagnostics()
	local P = ns.Print
	local _, _, _, toc = GetBuildInfo()
	local g = ns.G()
	P("---- " .. L["diagnostics"] .. " ----")
	P("Client interface: " .. tostring(toc) .. "  ·  addon " .. ns.VERSION .. "  ·  locale " .. GetLocale())
	P("Character: " .. tostring(ns.me) .. "  ·  guild key: " .. tostring(ns.gkey) .. (g and g.clubId and ("  ·  club " .. g.clubId) or ""))
	P("Rank index: " .. tostring(ns.MyRankIndex()) .. "  ·  can edit rules: " .. tostring(ns.CanEditRules())
		.. "  ·  roster: " .. tostring(ns.rosterCount) .. (ns.rosterReady and "" or " (not loaded)"))
	P("Secret-value API: " .. tostring(_G.issecretvalue ~= nil) .. "  ·  C_DamageMeter: " .. tostring(C_DamageMeter ~= nil))
	local dmgType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone
	local v, why = ns.Tracker.MeterLocalTotal(dmgType)
	P("Overall damage read now: " .. tostring(v) .. (why and ("  (" .. why .. ")") or ""))
	P("Price source: " .. tostring(ns.PriceSourceName() or "vendor only")
		.. "  ·  LibDataBroker: " .. tostring(_G.LibStub and _G.LibStub("LibDataBroker-1.1", true) ~= nil))
	local locked = C_ChatInfo.InChatMessagingLockdown and select(2, pcall(C_ChatInfo.InChatMessagingLockdown))
	P("Chat lockdown: " .. tostring(locked) .. "  ·  in instance: " .. tostring(IsInInstance())
		.. "  ·  send queue: " .. ns.Comm.QueueLength() .. "  ·  sharing: " .. tostring(ns.db.share))
	if g then
		local me = ns.GetPlayer(g, ns.me)
		local today = me and me.days[ns.Today()] or {}
		P(string.format("Today: played %s, gold %s, xp %s, damage %s, quests %s, loot value %s",
			ns.FormatTime(today.playtime), ns.FormatMoney(ns.MetricTotal(today, "gold", g)),
			ns.FormatNumber(today.xp or 0), ns.FormatNumber(today.damage or 0), tostring(today.quests or 0),
			ns.FormatMoney(ns.MetricTotal(today, "loot", g))))
		P("Players stored in this guild: " .. ns.CountPlayers(g))
	end
	for name in pairs(ns.nameClashes or {}) do
		P("|cffffaa40" .. string.format("Two guild members share the same name: %s. Guild Ranks can't tell them apart.", name) .. "|r")
	end
	ns.SyncDiagnostics(P)
	local missing = {}
	for ev in pairs(ns.unsupportedEvents) do missing[#missing + 1] = ev end
	if #missing > 0 then P("Events not available on this client: " .. table.concat(missing, ", ")) end
end

-- Guild sync timing: how long sending and receiving take in your guild
function ns.SyncDiagnostics(P)
	local C, st = ns.Comm, ns.Comm.stats
	local g = ns.G()
	local function ago(t) return t and string.format(L["%s ago"], ns.FormatCountdown(time() - t)) or L["never"] end
	P("---- " .. L["guild sync"] .. " ----")
	if g then P(L["Week"] .. ": " .. ns.ResetDescription(g)) end
	local paused = ""
	if not C.CanSend() then
		paused = "  ·  |cffffcc00" .. ((g and not g.solo and IsInGuild()) and (IsInInstance() and L["paused inside instances"]
			or L["paused (chat lockdown)"]) or L["not in a guild"]) .. "|r"
	end
	P(string.format(L["This session: sent %d, received %d (%d relayed for offline members)"], st.sent, st.received, st.relayed))
	local wait = C.SecondsToSend()
	P(string.format(L["Waiting to send: %d message(s), about %s"], C.QueueLength(),
		wait < 60 and string.format("%d s", math.ceil(wait)) or ns.FormatCountdown(wait)) .. paused)
	if st.lastBatch then
		P(string.format(L["Last send: %d message(s) in %d s (%s)"], st.lastBatch.n, math.floor(st.lastBatch.secs + 0.5), ago(st.lastBatch.at)))
	end
	local f = C.FullSyncInfo()
	if f then
		P(string.format(L["Last full sync: %d message(s) from %d member(s) in %d s (%s)%s"], f.msgs, f.members,
			math.floor(f.secs + 0.5), ago(f.at), f.busy and ("  ·  " .. L["still arriving"]) or ""))
	else
		P(L["Last full sync: none yet (/granks sync)"])
	end
	if g and not g.solo then
		local list = {}
		for key, p in pairs(g.players) do
			local t = math.max(p.seen or 0, p.relayedAt or 0)
			if key ~= ns.me and t > 0 then list[#list + 1] = { key = key, t = t, relayed = (p.relayedAt or 0) > (p.seen or 0) } end
		end
		table.sort(list, function(a, b) return a.t > b.t end)
		local parts = {}
		for i = 1, math.min(8, #list) do
			local e = list[i]
			parts[#parts + 1] = ns.ShortName(e.key) .. " " .. ago(e.t) .. (e.relayed and (" (" .. L["relayed"] .. ")") or "")
		end
		P(L["Latest data from guildmates"] .. ": " .. (#parts > 0 and table.concat(parts, ", ") or L["none yet"])
			.. (#list > 8 and string.format(L[" and %d more"], #list - 8) or ""))
	end
end

---------------------------------------------------------------------------
-- Slash commands and addon compartment
---------------------------------------------------------------------------
SLASH_GUILDRANKS1 = "/granks"
SLASH_GUILDRANKS2 = "/guildranks"
SlashCmdList.GUILDRANKS = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "show" then
		UI.Toggle()
	elseif msg == "members" or msg == "settings" or msg == "hall" or msg == "me" then
		UI.Toggle(msg)
	elseif msg == "sync" then
		ns.Comm.SyncNow()
		ns.Print(L["Asked the guild for fresh data."])
	elseif msg == "discord" then
		ns.ShowDiscordCopy(ns.V(), ns.db.view.period)
	elseif msg == "bar" then
		ns.Bar.Toggle()
	elseif msg == "diag" then
		ns.Diagnostics()
	elseif msg == "selftest" or msg == "test" then
		ns.Tools.SelfTest()
	elseif msg == "demo" then
		ns.Tools.Demo(true)
	elseif msg == "demo off" then
		ns.Tools.Demo(false)
	elseif msg == "log" then
		ns.Tools.PrintLog()
	elseif msg == "weekly" then
		if not (ns.G() and ns.Alerts.ShowWeeklyPopup(ns.G())) then ns.Print(L["No results for last week yet."]) end
	elseif msg == "recap" then
		ns.ShowRecap()
	elseif msg == "invite" then
		ns.Invite.Show()
	elseif msg == "welcome" then
		UI.Show("list")
		ns.Welcome.Show(true)
	elseif msg == "minimap" then
		ns.db.ui.minimap.hide = not ns.db.ui.minimap.hide
		local icon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
		if icon then
			if ns.db.ui.minimap.hide then icon:Hide(ADDON) else icon:Show(ADDON) end
		end
	else
		ns.Print("/granks  " .. L["open the leaderboard"])
		ns.Print("/granks me | members | hall | settings  " .. L["open those pages"])
		ns.Print("/granks recap  " .. L["show your session recap"])
		ns.Print("/granks discord  " .. L["copy the results for Discord"])
		ns.Print("/granks invite  " .. L["invite guildmates to install Guild Ranks"])
		ns.Print("/granks bar  " .. L["show or hide the session bar"])
		ns.Print("/granks weekly  " .. L["show last week's results again"])
		ns.Print("/granks sync  " .. L["ask the guild for fresh data"])
		ns.Print("/granks minimap  " .. L["show or hide the minimap button"])
		ns.Print("/granks selftest | log | demo [off] | diag  " .. L["testing tools"])
	end
end

function GuildRanks_OnAddonCompartmentClick()
	UI.Toggle()
end

function GuildRanks_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:AddLine(L["Guild Ranks"])
	GameTooltip:AddLine(L["Click to open the guild leaderboard."], 1, 1, 1)
	GameTooltip:Show()
end

function GuildRanks_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
