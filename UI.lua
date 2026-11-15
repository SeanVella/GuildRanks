-- Guild Ranks: main window (leaderboard, members, settings), slash commands
local ADDON, ns = ...
local L = ns.L
local UI = {}
ns.UI = UI

local ROW_H = 20
local frame, views, current = nil, {}, "list"
local subtitle, memberCount, resetText, footerText, valueHeader, emptyText, content
local rows, memberRows = {}, {}
local controls, w = {}, {}
local CreateMain -- defined below

---------------------------------------------------------------------------
-- Widget helpers
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

-- Modern dropdown, with a click-to-cycle button as a fallback
local function MakeDropdown(parent, width, getOptions, getValue, setValue)
	local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dd and dd.SetupMenu then
		dd:SetWidth(width)
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
		for _, o in ipairs(getOptions()) do
			if o.value == getValue() then self:SetText(o.text) end
		end
	end
	b:SetScript("OnClick", function(self)
		local opts, idx = getOptions(), 1
		for i, o in ipairs(opts) do
			if o.value == getValue() then idx = i end
		end
		setValue(opts[idx % #opts + 1].value)
		self:Refresh()
	end)
	b:Refresh()
	return b
end

local function MakeCheck(parent, label, onClick)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb.label = FS(cb, "GameFontHighlight")
	cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb.label:SetText(label)
	cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
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

local function MakeScroll(parent, top)
	local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
	if not ok or not sf then sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate") end
	sf:SetPoint("TOPLEFT", 18, top)
	sf:SetPoint("BOTTOMRIGHT", -38, 0)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(530, 1)
	sf:SetScrollChild(child)
	return sf, child
end

---------------------------------------------------------------------------
-- Leaderboard
---------------------------------------------------------------------------
local RANK_COLORS = { "|cffffd700", "|cffc7c7cf", "|cffcd7f32" }

local function ShowRowTooltip(self)
	local d = self.data
	if not d then return end
	local g = ns.V()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ClassColored(d.key, d.class))
	if ns.PlaytimeShownFor(g, d.key) then
		GameTooltip:AddLine(string.format(L["Level %d  ·  %s played"], d.level or 0, ns.FormatTime(d.playtime)), 0.8, 0.8, 0.8)
	else
		GameTooltip:AddLine(string.format(L["Level %d"], d.level or 0), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine(" ")
	if d.cats then
		GameTooltip:AddDoubleLine(L["Guild score"], tostring(d.score), 1, 0.82, 0, 1, 0.82, 0)
		for _, cat in ipairs(ns.SCORE_CATEGORIES) do
			GameTooltip:AddDoubleLine("  " .. cat.label, string.format("%d", math.floor(d.cats[cat.key] + 0.5)), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine(" ")
	end
	local history = ns.Hall.History(g, d.key, 6)
	if #history > 0 then
		GameTooltip:AddLine(L["Recent weeks"], 1, 0.82, 0)
		for _, hw in ipairs(history) do
			local t = ns.KeyToTime(hw.from)
			GameTooltip:AddDoubleLine("  " .. (t and date("%d %b", t) or hw.from),
				string.format(L["#%d of %d  ·  score %d"], hw.rank, hw.n, hw.score), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
		end
		local mvps = ns.Hall.MVPCount(g, d.key)
		if mvps > 0 then GameTooltip:AddLine(string.format(L["MVP %d time(s)"], mvps), 1, 0.82, 0) end
		GameTooltip:AddLine(" ")
	end
	local hours = d.playtime / 3600
	for _, m in ipairs(ns.METRICS) do
		if m.key ~= "playtime" and m.key ~= "score" then
			local total = ns.MetricTotal(d.bucket, m.key, g)
			local right = ns.FormatValue(m, total, false)
			if hours > 0 and m.rate then right = right .. "  |cff999999(" .. ns.FormatValue(m, total / hours, true) .. ")|r" end
			GameTooltip:AddDoubleLine(m.short, right, 1, 1, 1, 1, 1, 1)
		end
	end
	local any = false
	for _, src in ipairs(ns.GOLD_SOURCES) do
		local v = d.bucket["g_" .. src] or 0
		if v > 0 then
			if not any then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(L["Gold by source"], 1, 0.82, 0)
				any = true
			end
			local label = ns.GOLD_SOURCE_LABELS[src]
			if not g.rules.gold[src] then label = label .. " |cff999999(" .. L["not counted"] .. ")|r" end
			GameTooltip:AddDoubleLine(label, ns.FormatMoney(v), 1, 1, 1, 1, 1, 1)
		end
	end
	if d.version then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Guild Ranks"] .. " " .. d.version, 0.6, 0.6, 0.6)
	end
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
	r.name = FS(r, "GameFontHighlight", "LEFT"); r.name:SetPoint("LEFT", 38, 0); r.name:SetWidth(220)
	r.level = FS(r, "GameFontHighlight", "CENTER"); r.level:SetPoint("LEFT", 264, 0); r.level:SetWidth(36)
	r.value = FS(r, "GameFontHighlight", "RIGHT"); r.value:SetPoint("LEFT", 305, 0); r.value:SetWidth(135)
	r.played = FS(r, "GameFontHighlightSmall", "RIGHT"); r.played:SetPoint("LEFT", 450, 0); r.played:SetWidth(75)
	r:SetScript("OnEnter", ShowRowTooltip)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = r
	return r
end

local function RefreshList(g)
	local v = ns.db.view
	if v.metric == "playtime" and g.rules.showPlaytime == false then v.metric = "score" end
	resetText:SetText(ns.ResetDescription(g))
	local showPlayed = g.rules.showPlaytime ~= false
	controls.playedHeader:SetShown(showPlayed)
	local data, unranked, metric, useRate = ns.BuildBoard(g, v.metric, v.period, v.perHour, v.bracket)
	local period = ns.PERIOD_BY_KEY[v.period] or ns.PERIODS[2]

	subtitle:SetText(string.format("%s%s  ·  %s (%s)", metric.label, useRate and (" " .. L["per hour"]) or "",
		period.label, ns.PeriodDescription(period.key, g)))
	valueHeader:SetText(metric.key == "score" and L["Score"] or (useRate and L["Per hour"] or L["Total"]))
	if metric.rate then controls.perHour:Enable() else controls.perHour:Disable() end
	controls.perHour:SetChecked(v.perHour)

	local mvp, spoon = ns.WeeklyAwards(g)
	if mvp then
		controls.mvp:SetText(string.format(L["Last week's MVP: %s (%d)"], ClassColored(mvp.name, mvp.class), mvp.score))
	else
		controls.mvp:SetText(L["Last week's MVP: not enough data yet"])
	end
	controls.spoonBox:SetShown(g.rules.showSpoon)
	if spoon then
		controls.spoon:SetText(string.format(L["Wooden spoon: %s (%d)"], ClassColored(spoon.name, spoon.class), spoon.score))
	else
		controls.spoon:SetText(L["Wooden spoon: not enough data yet"])
	end

	-- Weekly challenge and guild goal
	local leader, cmetric = ns.ChallengeLeader(g, "week")
	if g.rules.challengeMetric and cmetric then
		local prize = g.rules.challengePrize and ("  ·  " .. L["prize"] .. ": " .. g.rules.challengePrize) or ""
		controls.challenge:SetText(string.format(L["Challenge: most %s"], cmetric.short .. "/h")
			.. (leader and ("  ·  " .. string.format(L["leader %s"], ClassColored(leader.name, leader.class))) or "") .. prize)
	else
		controls.challenge:SetText(L["No weekly challenge set"])
	end
	local cur, target, gmetric = ns.GoalProgress(g, "week")
	if cur then
		local pct = math.min(1, cur / target)
		controls.goalFill:SetWidth(math.max(1, 262 * pct))
		controls.goal:SetText(string.format(L["Guild goal: %s / %s %s"], ns.FormatValue(gmetric, cur, false),
			ns.FormatValue(gmetric, target, false), gmetric.short))
	else
		controls.goalFill:SetWidth(1)
		controls.goal:SetText(L["No guild goal set"])
	end

	for i, d in ipairs(data) do
		local r = GetRow(i)
		r.data = d
		r.rank:SetText((RANK_COLORS[i] or "|cffffffff") .. i .. ".|r")
		r.name:SetText(ClassColored(d.name, d.class) .. ns.Hall.Badge(g, d.key))
		r.level:SetText(d.level or "?")
		r.value:SetText(ns.FormatValue(metric, d.value, useRate))
		if not showPlayed then
			r.played:SetText("")
		elseif ns.PlaytimeShownFor(g, d.key) then
			r.played:SetText(ns.FormatTime(d.playtime))
		else
			r.played:SetText("|cff808080" .. L["hidden"] .. "|r")
		end
		if d.key == ns.me then
			r.bg:SetColorTexture(0.2, 0.8, 0.4, 0.18)
		else
			r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
		end
		r:Show()
	end
	for i = #data + 1, #rows do
		rows[i].data = nil
		rows[i]:Hide()
	end
	content:SetHeight(math.max(1, #data * ROW_H))

	if #data == 0 then
		local needsTime = useRate or metric.lowerIsBetter or metric.key == "score"
		emptyText:SetText(L["No rankings yet for this view."] .. "\n" .. (needsTime
			and string.format(L["Members need Guild Ranks installed and at least %d min played in this period."], g.rules.minMinutes)
			or L["Members need Guild Ranks installed."]))
		emptyText:Show()
	else
		emptyText:Hide()
	end

	local extra = unranked > 0 and ("  ·  " .. string.format(L["%d under %d min (not ranked)"], unranked, g.rules.minMinutes)) or ""
	local last = ns.Comm.lastReceived and date("%H:%M", ns.Comm.lastReceived) or L["never"]
	footerText:SetText(string.format(L["%d players tracked%s  ·  last guild update %s"], ns.CountPlayers(g), extra, last))
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

	subtitle:SetText(useRoster
		and string.format(L["%d members  ·  %d use Guild Ranks  ·  invite the rest to join in!"], #list, withAddon)
		or L["Roster is only available for your current guild"])
	footerText:SetText(canEdit and L["Officers: use Exclude to remove someone (e.g. a cheater) from the rankings."] or "")
end

---------------------------------------------------------------------------
-- Settings view
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

local function RefreshSettings(g)
	if w.pendingFor ~= g then LoadPending(g) end
	local pend, r = w.pending, g.rules
	local can = ns.CanEditRules(g)
	local isGM = g.solo or (g == ns.G() and ns.IsGuildMaster())

	subtitle:SetText(L["Settings"] .. "  ·  " .. g.name)
	w.share:SetChecked(ns.db.share)
	w.bar:SetChecked(ns.db.ui.bar.show)
	w.alerts:SetChecked(ns.db.alerts)
	w.popup:SetChecked(ns.db.weeklyPopup)
	w.announceLevel:SetChecked(ns.db.announceLevel)
	w.showPlay:SetChecked(ns.db.showPlay ~= false)
	w.info:SetText(g.demo and L["Sample data: rules can't be changed here."]
		or (g.solo and L["You're not in a guild: rankings only include your own characters."])
		or (can and L["You can change these rules. Saving shares them with the whole guild."])
		or L["Only the Guild Master and chosen ranks can change these rules."])
	w.by:SetText(r.by and string.format(L["Last set by %s on %s"], r.by, date("%d %b %H:%M", r.version)) or L["Using default rules"])

	for _, box in ipairs({ w.minBox, w.prizeBox, w.goalBox }) do
		if box.SetEnabled then box:SetEnabled(can) end
	end
	if not w.minBox:HasFocus() then w.minBox:SetText(tostring(pend.minMinutes)) end
	if not w.prizeBox:HasFocus() then w.prizeBox:SetText(pend.challengePrize or "") end
	if not w.goalBox:HasFocus() then
		local target = pend.goalTarget or 0
		w.goalBox:SetText(target > 0 and tostring(GoalIsMoney(pend.goalMetric) and math.floor(target / 10000) or target) or "")
	end
	w.goalUnit:SetText(GoalIsMoney(pend.goalMetric) and L["gold"] or "")
	for _, ctl in ipairs({ w.reset, w.resetHour, w.itemValue, w.save, w.challenge, w.goal }) do
		if can then ctl:Enable() else ctl:Disable() end
	end
	if isGM and not g.solo then w.manager:Enable() else w.manager:Disable() end
	for _, cb in ipairs({ w.spoon, w.announceMVP, w.showPlaytime }) do
		if can then cb:Enable() else cb:Disable() end
	end
	w.showPlaytime:SetChecked(pend.showPlaytime)
	w.spoon:SetChecked(pend.showSpoon)
	w.announceMVP:SetChecked(pend.announceMVP)
	for src, cb in pairs(w.gold) do
		cb:SetChecked(pend.gold[src])
		if can then cb:Enable() else cb:Disable() end
	end

	local price = ns.PriceSourceName()
	w.status:SetText(string.format(
		L["Addon version: %s%s\nDamage meter: %s\nAuction prices from: %s\nMessages waiting to send: %d%s"],
		ns.VERSION, ns.newerVersion and (" |cffffcc00(" .. string.format(L["%s available"], ns.newerVersion) .. ")|r") or "",
		ns.Tracker.state.meterStatus, price or L["none (install TradeSkillMaster or Auctionator)"],
		ns.Comm.QueueLength(), IsInInstance() and ("  (" .. L["paused inside instances"] .. ")") or ""))
	footerText:SetText("")
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
function UI.Refresh()
	if not frame or not frame:IsShown() then return end
	local g = ns.V()
	if not g then
		subtitle:SetText(L["Loading your guild..."])
		return
	end
	local isCurrent = g == ns.G()
	if g.solo then
		memberCount:SetText(L["Not in a guild"])
	elseif isCurrent and ns.rosterReady then
		local with = 0
		for key in pairs(ns.roster) do if g.players[key] then with = with + 1 end end
		memberCount:SetText(string.format(L["%d members · %d use the addon"], ns.rosterCount, with))
	else
		memberCount:SetText(isCurrent and "" or L["(one of your other characters' guilds)"])
	end
	resetText:SetText("")
	if current == "settings" then
		RefreshSettings(g)
	elseif current == "members" then
		RefreshMembers(g)
	elseif current == "hall" then
		RefreshHall(g)
	else
		RefreshList(g)
	end
end

function UI.Show(view)
	if not ns.db then return end
	if not frame then CreateMain() end
	if not frame:IsShown() then frame:Show() end
	current = view or "list"
	for name, f in pairs(views) do f:SetShown(name == current) end
	controls.membersBtn:SetText(current == "members" and L["Back to ranks"] or L["Members"])
	controls.settingsBtn:SetText(current == "settings" and L["Back to ranks"] or L["Settings"])
	controls.hallBtn:SetText(current == "hall" and L["Back to ranks"] or L["Hall of Fame"])
	if current == "settings" then
		w.pendingFor = nil
		UI.Refresh()
		w.reset:Refresh(); w.resetHour:Refresh(); w.itemValue:Refresh(); w.manager:Refresh(); w.challenge:Refresh(); w.goal:Refresh()
	else
		UI.Refresh()
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
	v:SetPoint("TOPLEFT", 0, -84)
	v:SetPoint("BOTTOMRIGHT", 0, 60)
	views.list = v

	local function AwardBox(x, r, g, b)
		local box = CreateFrame("Frame", nil, v)
		box:SetPoint("TOPLEFT", x, -2)
		box:SetSize(270, 22)
		local bg = box:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(r, g, b, 0.25)
		local text = FS(box, "GameFontHighlightSmall", "CENTER")
		text:SetPoint("CENTER")
		text:SetWidth(262)
		return text, box
	end
	controls.mvp = AwardBox(20, 1, 0.75, 0.1)
	controls.spoon, controls.spoonBox = AwardBox(298, 0.5, 0.5, 0.5)
	local challengeBox
	controls.challenge, challengeBox = AwardBox(20, 0.2, 0.45, 0.9)
	challengeBox:SetPoint("TOPLEFT", 20, -28)
	local goalBox
	controls.goal, goalBox = AwardBox(298, 0.25, 0.25, 0.25)
	goalBox:SetPoint("TOPLEFT", 298, -28)
	controls.goalFill = goalBox:CreateTexture(nil, "BORDER")
	controls.goalFill:SetPoint("TOPLEFT", 4, -4)
	controls.goalFill:SetPoint("BOTTOMLEFT", 4, 4)
	controls.goalFill:SetWidth(1)
	controls.goalFill:SetColorTexture(0.2, 0.8, 0.3, 0.5)

	local Y = -56
	Label(v, L["Ranking"], 22, Y - 6)
	Label(v, L["Period"], 232, Y - 6)
	Label(v, L["Level"], 362, Y - 6)
	local view = ns.db.view
	controls.metric = MakeDropdown(v, 200, function() return ns.RankingChoices(ns.V()) end,
		function() return view.metric end, function(val) view.metric = val; UI.Refresh() end)
	controls.metric:SetPoint("TOPLEFT", 20, Y - 20)
	controls.period = MakeDropdown(v, 120, function()
		local o = {}
		for _, p in ipairs(ns.PERIODS) do o[#o + 1] = { value = p.key, text = p.label } end
		return o
	end, function() return view.period end, function(val) view.period = val; UI.Refresh() end)
	controls.period:SetPoint("TOPLEFT", 230, Y - 20)
	controls.bracket = MakeDropdown(v, 100, ns.Brackets, function() return view.bracket end,
		function(val) view.bracket = val; UI.Refresh() end)
	controls.bracket:SetPoint("TOPLEFT", 360, Y - 20)
	controls.perHour = MakeCheck(v, L["Per hour"], function(checked) view.perHour = checked; UI.Refresh() end)
	controls.perHour:SetPoint("TOPLEFT", 475, Y - 20)

	local hdr = CreateFrame("Frame", nil, v)
	hdr:SetPoint("TOPLEFT", 18, Y - 52)
	hdr:SetSize(530, 18)
	local h1 = FS(hdr, "GameFontNormalSmall", "RIGHT"); h1:SetPoint("LEFT", 0, 0); h1:SetWidth(28); h1:SetText("#")
	local h2 = FS(hdr, "GameFontNormalSmall"); h2:SetPoint("LEFT", 38, 0); h2:SetText(L["Name"])
	local h3 = FS(hdr, "GameFontNormalSmall", "CENTER"); h3:SetPoint("LEFT", 264, 0); h3:SetWidth(36); h3:SetText(L["Lvl"])
	valueHeader = FS(hdr, "GameFontNormalSmall", "RIGHT"); valueHeader:SetPoint("LEFT", 305, 0); valueHeader:SetWidth(135)
	local h5 = FS(hdr, "GameFontNormalSmall", "RIGHT"); h5:SetPoint("LEFT", 450, 0); h5:SetWidth(75); h5:SetText(L["Played"])
	controls.playedHeader = h5

	local _, child = MakeScroll(v, Y - 72)
	content = child
	emptyText = FS(v, "GameFontDisable", "CENTER")
	emptyText:SetWordWrap(true)
	emptyText:SetPoint("TOP", 0, -150)
	emptyText:SetWidth(460)
end

local function BuildMembers()
	local v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", 0, -84)
	v:SetPoint("BOTTOMRIGHT", 0, 60)
	v:Hide()
	views.members = v
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

local function BuildSettings()
	local v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", 0, -84)
	v:SetPoint("BOTTOMRIGHT", 0, 60)
	v:Hide()
	views.settings = v

	-- Personal settings
	Label(v, L["You"], 22, -2, "GameFontNormal")
	w.share = MakeCheck(v, L["Share my stats with my guild"], function(checked) ns.Comm.SetShare(checked) end)
	w.share:SetPoint("TOPLEFT", 20, -18)
	w.bar = MakeCheck(v, L["Show session bar"], function(checked) ns.Bar.SetShown(checked) end)
	w.bar:SetPoint("TOPLEFT", 300, -18)
	w.alerts = MakeCheck(v, L["Rank-change alerts"], function(checked) ns.db.alerts = checked end)
	w.alerts:SetPoint("TOPLEFT", 20, -42)
	w.popup = MakeCheck(v, L["Weekly results popup"], function(checked) ns.db.weeklyPopup = checked end)
	w.popup:SetPoint("TOPLEFT", 300, -42)
	w.announceLevel = MakeCheck(v, L["Announce my level-ups in guild chat"], function(checked) ns.db.announceLevel = checked end)
	w.announceLevel:SetPoint("TOPLEFT", 20, -66)
	w.showPlay = MakeCheck(v, L["Show my play time to my guild"], function(checked) ns.Comm.SetShowPlay(checked) end)
	w.showPlay:SetPoint("TOPLEFT", 300, -66)

	-- Guild rules
	Label(v, L["Guild rules"], 22, -96, "GameFontNormal")
	w.info = FS(v, "GameFontHighlightSmall"); w.info:SetPoint("TOPLEFT", 22, -112)
	w.by = FS(v, "GameFontDisableSmall"); w.by:SetPoint("TOPLEFT", 22, -126)

	Label(v, L["Weekly reset (realm time)"], 22, -146)
	w.reset = MakeDropdown(v, 100, function()
		local o = {}
		for i, name in ipairs(ns.WEEKDAYS) do o[#o + 1] = { value = i, text = name } end
		return o
	end, function() return w.pending and w.pending.resetDay end, function(val) w.pending.resetDay = val end)
	w.reset:SetPoint("TOPLEFT", 20, -160)
	w.resetHour = MakeDropdown(v, 70, function()
		local o = {}
		for h = 0, 23 do o[#o + 1] = { value = h, text = string.format("%02d:00", h) } end
		return o
	end, function() return w.pending and w.pending.resetHour end, function(val) w.pending.resetHour = val end)
	w.resetHour:SetPoint("TOPLEFT", 126, -160)

	Label(v, L["Min. play time (min)"], 206, -146)
	w.minBox = CreateFrame("EditBox", nil, v, "InputBoxTemplate")
	w.minBox:SetSize(60, 22)
	w.minBox:SetPoint("TOPLEFT", 212, -160)
	w.minBox:SetAutoFocus(false)
	w.minBox:SetNumeric(true)
	w.minBox:SetMaxLetters(4)
	local function readMin(self) w.pending.minMinutes = tonumber(self:GetText()) or w.pending.minMinutes end
	w.minBox:SetScript("OnEnterPressed", function(self) readMin(self); self:ClearFocus() end)
	w.minBox:SetScript("OnEditFocusLost", readMin)
	w.minBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	Label(v, L["Who can change rules (Guild Master only)"], 322, -146)
	w.manager = MakeDropdown(v, 210, ns.RankChoices, function() return w.pending and w.pending.managerRank end,
		function(val) w.pending.managerRank = val end)
	w.manager:SetPoint("TOPLEFT", 320, -160)

	Label(v, L["Loot value uses"], 22, -192)
	w.itemValue = MakeDropdown(v, 250, function()
		return {
			{ value = "vendor", text = L["Vendor price (fair for everyone)"] },
			{ value = "auction", text = L["Auction price (TSM / Auctionator)"] },
		}
	end, function() return w.pending and w.pending.itemValue end, function(val) w.pending.itemValue = val end)
	w.itemValue:SetPoint("TOPLEFT", 20, -206)
	w.spoon = MakeCheck(v, L["Show the Wooden spoon (last place)"], function(checked) w.pending.showSpoon = checked end)
	w.spoon:SetPoint("TOPLEFT", 300, -188)
	w.announceMVP = MakeCheck(v, L["Post last week's MVP in guild chat"], function(checked) w.pending.announceMVP = checked end)
	w.announceMVP:SetPoint("TOPLEFT", 300, -210)
	w.showPlaytime = MakeCheck(v, L["Show play time (column and ranking)"], function(checked) w.pending.showPlaytime = checked end)
	w.showPlaytime:SetPoint("TOPLEFT", 300, -232)

	Label(v, L["Count gold from"], 22, -258)
	w.gold = {}
	for i, src in ipairs(ns.GOLD_SOURCES) do
		local cb = MakeCheck(v, ns.GOLD_SOURCE_LABELS[src], function(checked) w.pending.gold[src] = checked end)
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		cb:SetPoint("TOPLEFT", 20 + col * 180, -272 - row * 24)
		w.gold[src] = cb
	end

	Label(v, L["Weekly challenge"], 22, -348)
	w.challenge = MakeDropdown(v, 200, ns.ChallengeChoices, function() return w.pending and w.pending.challengeMetric end,
		function(val) w.pending.challengeMetric = val end)
	w.challenge:SetPoint("TOPLEFT", 20, -362)
	Label(v, L["Prize (optional)"], 236, -348)
	w.prizeBox = CreateFrame("EditBox", nil, v, "InputBoxTemplate")
	w.prizeBox:SetSize(200, 22)
	w.prizeBox:SetPoint("TOPLEFT", 242, -362)
	w.prizeBox:SetAutoFocus(false)
	w.prizeBox:SetMaxLetters(40)
	local function readPrize(self) w.pending.challengePrize = ns.CleanText(self:GetText(), 40) end
	w.prizeBox:SetScript("OnEnterPressed", function(self) readPrize(self); self:ClearFocus() end)
	w.prizeBox:SetScript("OnEditFocusLost", readPrize)
	w.prizeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	Label(v, L["Guild goal (combined this week)"], 22, -394)
	w.goal = MakeDropdown(v, 200, ns.GoalChoices, function() return w.pending and w.pending.goalMetric end,
		function(val) w.pending.goalMetric = val; UI.Refresh() end)
	w.goal:SetPoint("TOPLEFT", 20, -408)
	Label(v, L["Target"], 236, -394)
	w.goalBox = CreateFrame("EditBox", nil, v, "InputBoxTemplate")
	w.goalBox:SetSize(100, 22)
	w.goalBox:SetPoint("TOPLEFT", 242, -408)
	w.goalBox:SetAutoFocus(false)
	w.goalBox:SetNumeric(true)
	w.goalBox:SetMaxLetters(9)
	local function readGoal(self)
		local n = tonumber(self:GetText()) or 0
		w.pending.goalTarget = GoalIsMoney(w.pending.goalMetric) and n * 10000 or n
	end
	w.goalBox:SetScript("OnEnterPressed", function(self) readGoal(self); self:ClearFocus() end)
	w.goalBox:SetScript("OnEditFocusLost", readGoal)
	w.goalBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	w.goalUnit = FS(v, "GameFontHighlightSmall"); w.goalUnit:SetPoint("LEFT", w.goalBox, "RIGHT", 6, 0)

	w.save = MakeButton(v, L["Save & share with guild"], 200, function()
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
		UI.Refresh()
	end)
	w.save:SetPoint("TOPLEFT", 20, -446)

	w.status = FS(v, "GameFontHighlightSmall")
	w.status:SetWordWrap(true)
	w.status:SetWidth(320)
	w.status:SetPoint("TOPLEFT", 240, -442)
end

local function BuildHall()
	local v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", 0, -84)
	v:SetPoint("BOTTOMRIGHT", 0, 60)
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

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	local title = FS(frame, "GameFontNormalLarge", "CENTER")
	title:SetPoint("TOP", 0, -16)
	title:SetText(L["Guild Ranks"])

	controls.guild = MakeDropdown(frame, 230, GuildOptions, function() return select(2, ns.V()) end, function(val)
		ns.db.view.guild = (val ~= ns.gkey) and val or nil
		w.pendingFor = nil
		UI.Refresh()
	end)
	controls.guild:SetPoint("TOPLEFT", 20, -38)
	memberCount = FS(frame, "GameFontHighlightSmall", "RIGHT")
	memberCount:SetPoint("TOPRIGHT", -26, -42)
	resetText = FS(frame, "GameFontDisableSmall", "RIGHT")
	resetText:SetPoint("TOPRIGHT", -26, -55)

	subtitle = FS(frame, "GameFontHighlightSmall", "CENTER")
	subtitle:SetPoint("TOP", 0, -68)
	subtitle:SetWidth(560)

	BuildList()
	BuildMembers()
	BuildSettings()
	BuildHall()

	footerText = FS(frame, "GameFontDisableSmall")
	footerText:SetPoint("BOTTOMLEFT", 22, 46)
	footerText:SetWidth(556)

	local sync = MakeButton(frame, L["Sync now"], 90, function()
		ns.Comm.SyncNow()
		ns.Print(L["Asked the guild for fresh data."])
	end)
	sync:SetPoint("BOTTOMLEFT", 20, 18)
	local copy = MakeButton(frame, L["Copy for Discord"], 125, function()
		ns.ShowDiscordCopy(ns.V(), ns.db.view.period)
	end)
	copy:SetPoint("LEFT", sync, "RIGHT", 6, 0)
	controls.settingsBtn = MakeButton(frame, L["Settings"], 105, function()
		UI.Show(current == "settings" and "list" or "settings")
	end)
	controls.settingsBtn:SetPoint("BOTTOMRIGHT", -20, 18)
	controls.membersBtn = MakeButton(frame, L["Members"], 105, function()
		UI.Show(current == "members" and "list" or "members")
	end)
	controls.membersBtn:SetPoint("RIGHT", controls.settingsBtn, "LEFT", -6, 0)
	controls.hallBtn = MakeButton(frame, L["Hall of Fame"], 105, function()
		UI.Show(current == "hall" and "list" or "hall")
	end)
	controls.hallBtn:SetPoint("RIGHT", controls.membersBtn, "LEFT", -6, 0)
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
	elseif msg == "members" or msg == "settings" or msg == "hall" then
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
	elseif msg == "minimap" then
		ns.db.ui.minimap.hide = not ns.db.ui.minimap.hide
		local icon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
		if icon then
			if ns.db.ui.minimap.hide then icon:Hide(ADDON) else icon:Show(ADDON) end
		end
	else
		ns.Print("/granks  " .. L["open the leaderboard"])
		ns.Print("/granks members | hall | settings  " .. L["open those pages"])
		ns.Print("/granks discord  " .. L["copy the results for Discord"])
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
