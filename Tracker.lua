-- Guild Ranks: tracks YOUR OWN character's stats (each member's addon tracks itself)
local ADDON, ns = ...
local T = {}
ns.Tracker = T

local state = {
	money = nil, moneyDeferred = false,
	xp = nil, xpMax = nil, level = nil,
	pending = nil, lastGain = nil,
	merchant = false, mail = false, ah = false, trade = false, loot = false,
	meterLast = {}, meterStatus = "not read yet",
	dirty = false,
}
T.state = state

---------------------------------------------------------------------------
-- Add a value to today's bucket and the all-time bucket
---------------------------------------------------------------------------
function ns.Add(field, amount)
	if not amount or amount == 0 or not ns.me or not ns.db then return end
	local g = ns.G()
	if not g then
		ns.QueueAdd(field, amount) -- guild not known yet (first seconds after login)
		return
	end
	local p = ns.GetPlayer(g, ns.me, true)
	local day = ns.Today()
	local b = p.days[day]
	if not b then
		b = {}
		p.days[day] = b
	end
	b[field] = (b[field] or 0) + amount
	p.all[field] = (p.all[field] or 0) + amount
	p.seen = time()
	state.dirty = true
	for i = 1, #ns.addHooks do ns.addHooks[i](field, amount) end
	ns.MarkChanged()
end

---------------------------------------------------------------------------
-- Global-string helpers (work with any client language)
---------------------------------------------------------------------------
-- Turns e.g. "%s dies, you gain %d experience." into "^(.-) dies, you gain "
local function GSPattern(gs)
	if type(gs) ~= "string" then return nil end
	local cut = gs:find("%d", 1, true)
	if cut then gs = gs:sub(1, cut - 1) end
	gs = gs:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	gs = gs:gsub("%%s", "(.-)")
	return "^" .. gs
end

---------------------------------------------------------------------------
-- Gold
---------------------------------------------------------------------------
local function SetPending(src, secs)
	state.pending = { src = src, expires = GetTime() + (secs or 2) }
end

local function GoldSource()
	local pend = state.pending
	if pend and GetTime() <= pend.expires then
		state.pending = nil
		return pend.src
	end
	if state.trade then return "trade" end
	if state.mail then return "mail" end
	if state.ah then return "ah" end
	if state.merchant then return "vendor" end
	if state.loot then return "loot" end
	return "other"
end

local function ReadMoney()
	local m = GetMoney()
	if not ns.Readable(m) then return nil end
	return m
end

local function OnMoney()
	local m = ReadMoney()
	if not m then
		state.moneyDeferred = true -- hidden right now (combat); re-read after combat
		return
	end
	state.moneyDeferred = false
	if state.money == nil then
		state.money = m
		return
	end
	local delta = m - state.money
	state.money = m
	if delta > 0 then
		local src = GoldSource()
		ns.Add("g_" .. src, delta)
		state.lastGain = { src = src, amount = delta, at = GetTime() }
	end
end
ns.On("PLAYER_MONEY", OnMoney)

ns.On("MERCHANT_SHOW", function() state.merchant = true end)
ns.On("MERCHANT_CLOSED", function() state.merchant = false end)
ns.On("MAIL_SHOW", function() state.mail = true end)
ns.On("MAIL_CLOSED", function() state.mail = false end)
ns.On("AUCTION_HOUSE_SHOW", function() state.ah = true end)
ns.On("AUCTION_HOUSE_CLOSED", function() state.ah = false end)
ns.On("TRADE_SHOW", function() state.trade = true end)
ns.On("TRADE_CLOSED", function()
	state.trade = false
	SetPending("trade", 2) -- trade money can arrive just after the window closes
end)
ns.On("LOOT_OPENED", function()
	state.loot = true
	if IsFishingLoot and IsFishingLoot() then ns.Add("gathers", 1) end
end)
ns.On("LOOT_CLOSED", function()
	state.loot = false
	SetPending("loot", 1)
end)
ns.On("CHAT_MSG_MONEY", function() SetPending("loot", 2) end) -- group loot share

-- Auction House sales arrive by mail as "seller" invoices
local function MailPending(index)
	local src = "mail"
	if GetInboxInvoiceInfo then
		local ok, invoiceType = pcall(GetInboxInvoiceInfo, index)
		if ok and invoiceType == "seller" then src = "ah" end
	end
	SetPending(src, 3)
end
if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", MailPending) end
if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", MailPending) end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
ns.On("QUEST_TURNED_IN", function(questID, xpReward, moneyReward)
	ns.Add("quests", 1)
	-- If the money arrived just before this event, re-label it as quest gold
	local lg = state.lastGain
	if lg and ns.Readable(moneyReward) and type(moneyReward) == "number" and moneyReward > 0
		and GetTime() - lg.at < 1.5 and lg.src ~= "quest" and lg.amount == moneyReward then
		ns.Add("g_" .. lg.src, -lg.amount)
		ns.Add("g_quest", lg.amount)
		lg.src = "quest"
	else
		SetPending("quest", 2)
	end
end)

---------------------------------------------------------------------------
-- Experience
---------------------------------------------------------------------------
local function ReadXP()
	local cur, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	if not (ns.Readable(cur) and ns.Readable(max) and ns.Readable(lvl)) then return nil end
	return cur, max, lvl
end

local function OnXP()
	local cur, max, lvl = ReadXP()
	if not cur then return end
	if state.xp == nil or not state.xpMax or state.xpMax <= 0 then
		state.xp, state.xpMax, state.level = cur, max, lvl
		return
	end
	local gain, levels = 0, 0
	local leveled = (lvl > state.level) or (cur < state.xp)
	if not leveled then
		gain = cur - state.xp
		levels = gain / state.xpMax
	else
		-- Level-up: the rest of the old level plus progress into the new one
		local newLevel = math.max(lvl, state.level + 1)
		local rest = math.max(0, state.xpMax - state.xp)
		gain = rest + cur
		levels = rest / state.xpMax + ((max > 0) and (cur / max) or 0) + math.max(0, newLevel - state.level - 1)
		lvl = newLevel
	end
	state.xp, state.xpMax, state.level = cur, max, lvl
	if gain > 0 then
		ns.Add("xp", gain)
		ns.Add("mlevels", levels * 1000)
	end
end
ns.On("PLAYER_XP_UPDATE", OnXP)

ns.On("PLAYER_LEVEL_UP", function(newLevel)
	local p = ns.me and ns.GetPlayer(ns.G(), ns.me)
	if p and ns.Readable(newLevel) then p.level = newLevel end
end)

---------------------------------------------------------------------------
-- Kills (from "X dies, you gain N experience" messages), crafting
---------------------------------------------------------------------------
local killPattern = GSPattern(_G.COMBATLOG_XPGAIN_FIRSTPERSON) or "^(.-) dies, you gain "
ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(text)
	if not ns.Readable(text) or type(text) ~= "string" then return end
	if text:find(killPattern) then ns.Add("kills", 1) end
end)

local createPatterns = {}
for _, name in ipairs({ "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE" }) do
	local pat = GSPattern(_G[name])
	if pat then createPatterns[#createPatterns + 1] = pat end
end
if #createPatterns == 0 then createPatterns[1] = "^You create: " end

-- "You receive loot: [item]" / "You receive loot: [item]x3." -> loot value
local lootPatterns = {}
for _, name in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
	local pat = GSPattern(_G[name])
	if pat then lootPatterns[#lootPatterns + 1] = pat end
end
if #lootPatterns == 0 then lootPatterns[1] = "^You receive loot: " end

local function AddLootValue(link, count, tries)
	local vendor, auction, pending = ns.ItemValues(link)
	if pending and (tries or 0) < 3 then
		C_Timer.After(1, function() AddLootValue(link, count, (tries or 0) + 1) end)
		return
	end
	if vendor and vendor > 0 then ns.Add("lv_vendor", vendor * count) end
	if auction and auction > 0 then ns.Add("lv_auction", auction * count) end
end

ns.On("CHAT_MSG_LOOT", function(text)
	if not ns.Readable(text) or type(text) ~= "string" then return end
	for _, pat in ipairs(createPatterns) do
		if text:find(pat) then
			ns.Add("crafts", 1)
			return
		end
	end
	for _, pat in ipairs(lootPatterns) do
		if text:find(pat) then
			local link = text:match("(|c.-|Hitem:.-|h.-|h|r)")
			if link and ns.ItemValues then
				local count = tonumber(text:match("|r[^%d]*(%d+)[^%d]*$")) or 1
				AddLootValue(link, count)
			end
			return
		end
	end
end)

---------------------------------------------------------------------------
-- Gathering (herbs, ore, skinning; fishing is counted from fishing loot)
---------------------------------------------------------------------------
-- Gathering spells by ID (Classic-era IDs; names are looked up in the client's
-- own language), plus English names as a fallback
local GATHER_IDS = {
	2366, 2368, 3570, 11993, 28695, 50300, 74519,   -- Herb Gathering
	2575, 2576, 3564, 10248, 29354, 50310, 74517,   -- Mining
	8613, 8617, 8618, 10768, 32678, 50305, 74522,   -- Skinning
}
T.GATHER_IDS, T.GATHER_SPELLS = {}, { ["Herb Gathering"] = true, ["Mining"] = true, ["Skinning"] = true }
for _, id in ipairs(GATHER_IDS) do T.GATHER_IDS[id] = true end
ns.OnLogin(function()
	for _, id in ipairs(GATHER_IDS) do
		local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
		if name and ns.Readable(name) then T.GATHER_SPELLS[name] = true end
	end
end)

local castFrame = CreateFrame("Frame")
castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
	if unit ~= "player" or not ns.Readable(spellID) or not ns.db then return end
	local name
	if C_Spell and C_Spell.GetSpellName then
		name = C_Spell.GetSpellName(spellID)
	elseif GetSpellInfo then
		name = GetSpellInfo(spellID)
	end
	if T.GATHER_IDS[spellID] or (name and ns.Readable(name) and T.GATHER_SPELLS[name]) then ns.Add("gathers", 1) end
end)

---------------------------------------------------------------------------
-- Deaths, bosses, dungeon/raid runs
---------------------------------------------------------------------------
ns.On("PLAYER_DEAD", function() ns.Add("deaths", 1) end)

ns.On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, groupSize, success)
	if not ns.Readable(success) or success ~= 1 then return end
	ns.Add("bosses", 1)
	local run = ns.me and ns.db.chars[ns.me].run
	if run then run.bosses = (run.bosses or 0) + 1 end
end)

local function FinishRun()
	local st = ns.db.chars[ns.me]
	if st.run and (st.run.bosses or 0) >= 1 then ns.Add("dungeons", 1) end
	st.run = nil
end

local function CheckInstance()
	if not ns.me then return end
	local inInstance, instanceType = IsInInstance()
	local st = ns.db.chars[ns.me]
	if inInstance and (instanceType == "party" or instanceType == "raid") then
		local instanceID = select(8, GetInstanceInfo())
		if not st.run or st.run.id ~= instanceID then
			FinishRun()
			st.run = { id = instanceID, bosses = 0 }
		end
	else
		FinishRun()
	end
end
ns.On("ZONE_CHANGED_NEW_AREA", CheckInstance)

---------------------------------------------------------------------------
-- Damage and healing via Blizzard's built-in damage meter (C_DamageMeter)
-- The meter is hidden from addons during combat, so we read the "Overall"
-- total after each fight and add the difference since the last read.
---------------------------------------------------------------------------
local function MeterLocalTotal(meterType)
	if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum
		and Enum.DamageMeterSessionType and meterType ~= nil) then
		return nil, "damage meter API not available"
	end
	local ok, result, why = pcall(function()
		local session = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Overall, meterType)
		if session == nil then return 0 end
		if not ns.Readable(session) then return nil, "hidden (secret value)" end
		local sources = session.combatSources
		if not sources then return 0 end
		for i = 1, #sources do
			local src = sources[i]
			if src.isLocalPlayer then
				local amt = src.totalAmount
				if amt == nil then return 0 end
				if not ns.Readable(amt) then return nil, "hidden (secret value)" end
				return amt
			end
		end
		return 0
	end)
	if not ok then return nil, "error: " .. tostring(result) end
	return result, why
end
T.MeterLocalTotal = MeterLocalTotal

local METER_FIELDS = { damage = "DamageDone", healing = "HealingDone" }

function T.SyncMeters()
	if not ns.me or UnitAffectingCombat("player") then return end
	for field, enumName in pairs(METER_FIELDS) do
		local meterType = Enum and Enum.DamageMeterType and Enum.DamageMeterType[enumName]
		local v, why = MeterLocalTotal(meterType)
		if type(v) == "number" then
			state.meterStatus = "OK"
			local last = state.meterLast[field]
			if last ~= nil then
				local d = v - last
				if d < 0 then d = v end -- meter was reset since the last read
				if d > 0 then ns.Add(field, d) end
			end
			state.meterLast[field] = v -- first read is the baseline
		else
			state.meterStatus = why or "unavailable"
		end
	end
end

ns.On("DAMAGE_METER_RESET", function()
	for k in pairs(state.meterLast) do state.meterLast[k] = 0 end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
	C_Timer.After(1.5, T.SyncMeters)
	if state.moneyDeferred then OnMoney() end
end)

---------------------------------------------------------------------------
-- Login / play time
---------------------------------------------------------------------------
ns.On("PLAYER_ENTERING_WORLD", function()
	if not ns.me then return end
	if state.money == nil then state.money = ReadMoney() end
	if state.xp == nil then
		local cur, max, lvl = ReadXP()
		if cur then state.xp, state.xpMax, state.level = cur, max, lvl end
	end
	CheckInstance()
	C_Timer.After(3, T.SyncMeters)
end)

ns.OnLogin(function()
	local lastTick = GetTime()
	local ticks = 0
	C_Timer.NewTicker(5, function()
		local now = GetTime()
		local dt = now - lastTick
		lastTick = now
		-- Count active time only: skip AFK and long gaps (loading screens)
		if dt > 0 and dt < 30 and not UnitIsAFK("player") then ns.Add("playtime", dt) end
		ticks = ticks + 1
		if ticks % 6 == 0 then T.SyncMeters() end -- every 30 s out of combat
	end)
end)
