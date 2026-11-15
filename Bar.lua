-- Guild Ranks: session bar — a small movable bar with your rank this week and
-- this session's gold/XP per hour and time to level. Optional (Settings or /granks bar).
local ADDON, ns = ...
local L = ns.L
local B = {}
ns.Bar = B

local session = { totals = {} }
B.session = session
local bar, cachedRank, rankAt = nil, nil, -1000

table.insert(ns.addHooks, function(field, amount)
	session.totals[field] = (session.totals[field] or 0) + amount
end)

-- Session numbers: goldPerHour, xpPerHour, lootPerHour, secondsToLevel (or nil), hours
function B.SessionStats()
	local g = ns.G()
	local t = session.totals
	local hours = (t.playtime or 0) / 3600
	local gold = g and ns.MetricTotal(t, "gold", g) or 0
	local loot = g and ns.MetricTotal(t, "loot", g) or 0
	local gph = hours > 0 and gold / hours or 0
	local xph = hours > 0 and (t.xp or 0) / hours or 0
	local lph = hours > 0 and loot / hours or 0
	local toLevel
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if xph > 0 and ns.Readable(cur) and ns.Readable(max) and max > 0 then
		toLevel = (max - cur) / xph * 3600
	end
	return gph, xph, lph, toLevel, hours
end

local function MyRank()
	if GetTime() - rankAt < 30 and cachedRank then return unpack(cachedRank) end
	rankAt = GetTime()
	local g = ns.G()
	cachedRank = { nil, 0, nil }
	if g then
		local list = ns.ComputeScores(g, "week", 0)
		cachedRank = { nil, #list, nil }
		for i, e in ipairs(list) do
			if e.key == ns.me then cachedRank = { i, #list, e.score } end
		end
	end
	return unpack(cachedRank)
end

function B.Text()
	local gph, xph, lph, toLevel, hours = B.SessionStats()
	local parts = {}
	local rank, total, score = MyRank()
	parts[#parts + 1] = rank and string.format("|TInterface\\Icons\\INV_Misc_Trophy_Gold:12:12|t #%d/%d · %d", rank, total, score)
		or ("|TInterface\\Icons\\INV_Misc_Trophy_Gold:12:12|t " .. L["not ranked yet"])
	if hours < 0.02 then
		parts[#parts + 1] = L["session just started"]
	else
		parts[#parts + 1] = ns.FormatMoney(gph) .. "/h"
		if UnitLevel("player") < ns.MaxLevel() then
			parts[#parts + 1] = ns.FormatNumber(xph) .. " " .. L["XP/h"]
			if toLevel then parts[#parts + 1] = "|cff999999" .. string.format(L["level in %s"], ns.FormatTime(toLevel)) .. "|r" end
		else
			parts[#parts + 1] = L["loot"] .. " " .. ns.FormatMoney(lph) .. "/h"
		end
	end
	return table.concat(parts, "  |  ")
end

local function Create()
	bar = CreateFrame("Button", "GuildRanksBar", UIParent, "BackdropTemplate")
	bar:SetSize(360, 24)
	bar:SetFrameStrata("MEDIUM")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bar:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	bar:SetBackdropColor(0, 0, 0, 0.7)
	local pt = ns.db.ui.bar.point
	if pt then bar:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else bar:SetPoint("TOP", 0, -120) end
	bar:SetScript("OnDragStart", bar.StartMoving)
	bar:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local p, _, rp, x, y = f:GetPoint()
		ns.db.ui.bar.point = { p, rp, x, y }
	end)
	bar:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns.UI.Toggle("settings") else ns.UI.Toggle() end
	end)
	bar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Guild Ranks session"])
		local gph, xph, lph, toLevel, hours = B.SessionStats()
		GameTooltip:AddDoubleLine(L["Session play time"], ns.FormatTime(hours * 3600), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Gold per hour"], ns.FormatMoney(gph), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["XP per hour"], ns.FormatNumber(xph), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Loot value per hour"], ns.FormatMoney(lph), 1, 1, 1, 1, 1, 1)
		if toLevel then GameTooltip:AddDoubleLine(L["Time to level"], ns.FormatTime(toLevel), 1, 1, 1, 1, 1, 1) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Drag to move  ·  Click: leaderboard  ·  Right-click: settings"], 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.text:SetPoint("CENTER")
end

function B.Refresh()
	if not bar then return end
	bar.text:SetText(B.Text())
	bar:SetWidth(math.max(200, (bar.text:GetStringWidth() or 300) + 24))
end

function B.SetShown(show)
	ns.db.ui.bar.show = show and true or false
	if show then
		if not bar then Create() end
		bar:Show()
		B.Refresh()
	elseif bar then
		bar:Hide()
	end
end

function B.Toggle() B.SetShown(not ns.db.ui.bar.show) end

ns.OnInit(function()
	ns.db.ui.bar = ns.db.ui.bar or { show = false }
end)

ns.OnLogin(function()
	if ns.db.ui.bar.show then B.SetShown(true) end
	C_Timer.NewTicker(5, function()
		if bar and bar:IsShown() then B.Refresh() end
	end)
end)
