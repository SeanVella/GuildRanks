-- Guild Ranks: optional integrations with popular addons. Each one is used only
-- if that addon is installed; nothing here is required.
--   * TradeSkillMaster / Auctionator: auction prices for the "Loot value" ranking
--   * LibDataBroker displays (Titan Panel, ElvUI data texts, Bazooka, ChocolateBar...)
--   * LibDBIcon: minimap button
local ADDON, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Item values
---------------------------------------------------------------------------
local function VendorPrice(link)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, _, _, _, _, _, _, _, _, _, sellPrice = getInfo(link)
	if not name then return nil end -- item data not loaded yet
	return sellPrice or 0
end

local function TSMPrice(link)
	local api = _G.TSM_API
	if not (api and api.GetCustomPriceValue and api.ToItemString) then return nil end
	local ok, value = pcall(function()
		return api.GetCustomPriceValue("dbmarket", api.ToItemString(link))
	end)
	if ok and type(value) == "number" and value > 0 then return value end
	return nil
end

local function AuctionatorPrice(link)
	local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
	if not (api and api.GetAuctionPriceByItemLink) then return nil end
	local ok, value = pcall(api.GetAuctionPriceByItemLink, ADDON, link)
	if ok and type(value) == "number" and value > 0 then return value end
	return nil
end

-- Returns vendorPrice, auctionPrice (auction falls back to vendor), pending (item not loaded)
function ns.ItemValues(link)
	local vendor = VendorPrice(link)
	if vendor == nil then
		local itemID = tonumber(link:match("item:(%d+)"))
		if itemID and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
		return nil, nil, true
	end
	local auction = TSMPrice(link) or AuctionatorPrice(link) or vendor
	return vendor, auction, false
end

function ns.PriceSourceName()
	if _G.TSM_API and _G.TSM_API.GetCustomPriceValue then return "TradeSkillMaster" end
	if _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1 then return "Auctionator" end
	return nil
end

---------------------------------------------------------------------------
-- LibDataBroker + minimap button (libraries are bundled in the release zip)
---------------------------------------------------------------------------
local broker

local function MySummary()
	local g = ns.G()
	if not g then return nil end
	local list = ns.ComputeScores(g, "week", 0)
	for i, e in ipairs(list) do
		if e.key == ns.me then return i, #list, e.score end
	end
	return nil, #list
end

local function UpdateBroker()
	if not broker then return end
	local rank, total, score = MySummary()
	broker.text = rank and string.format("#%d/%d · %d", rank, total, score) or L["Guild Ranks"]
end

ns.OnLogin(function()
	local LibStub = _G.LibStub
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	if not LDB then return end
	broker = LDB:NewDataObject(ADDON, {
		type = "data source",
		label = L["Guild Ranks"],
		text = L["Guild Ranks"],
		icon = "Interface\\AddOns\\GuildRanks\\Media\\Icon",
		OnClick = function(_, button)
			if button == "RightButton" then
				ns.UI.Toggle("settings")
			else
				ns.UI.Toggle()
			end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine(L["Guild Ranks"])
			local rank, total, score = MySummary()
			if rank then
				tt:AddLine(string.format(L["This week: #%d of %d (score %d)"], rank, total, score), 1, 1, 1)
			else
				tt:AddLine(L["Not ranked yet this week"], 0.8, 0.8, 0.8)
			end
			local mvp, spoon
			if ns.G() then mvp, spoon = ns.WeeklyAwards(ns.G()) end
			if mvp then
				tt:AddLine(string.format(L["Last week's MVP: %s (%d)"], mvp.name, mvp.score), 1, 0.82, 0)
				if spoon then tt:AddLine(string.format(L["Wooden spoon: %s (%d)"], spoon.name, spoon.score), 0.7, 0.7, 0.7) end
			end
			tt:AddLine(" ")
			tt:AddLine(L["Click: open leaderboard  ·  Right-click: settings"], 0.6, 0.6, 0.6)
		end,
	})
	local icon = LibStub("LibDBIcon-1.0", true)
	if icon then icon:Register(ADDON, broker, ns.db.ui.minimap) end
	C_Timer.NewTicker(30, UpdateBroker)
	C_Timer.After(5, UpdateBroker)
end)
