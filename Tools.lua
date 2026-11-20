-- Guild Ranks: in-game test tools
--   /granks selftest   checks every game feature the addon relies on (pass / warn / fail)
--   /granks demo       sample guild data to preview the window (and take screenshots)
--   /granks demo off   removes the sample data
--   /granks log        the last tracked changes and where they were counted
local ADDON, ns = ...
local L = ns.L
local T = {}
ns.Tools = T

---------------------------------------------------------------------------
-- Event log (last 50 tracked changes)
---------------------------------------------------------------------------
local LOG_MAX = 50
local log = {}
T.log = log

local FIELD_LABELS = {
	playtime = false, -- too frequent to log
	g_loot = "gold (loot)", g_quest = "gold (quest)", g_vendor = "gold (vendor)", g_ah = "gold (Auction House)",
	g_mail = "gold (mail)", g_trade = "gold (trade)", g_other = "gold (other)",
	xp = "XP", mlevels = false, damage = "damage", healing = "healing", kills = "kill", deaths = "death",
	quests = "quest", bosses = "boss kill", dungeons = "dungeon/raid run", gathers = "gathering", crafts = "craft",
	lv_vendor = "loot value (vendor)", lv_auction = false,
}

table.insert(ns.addHooks, function(field, amount)
	local label = FIELD_LABELS[field]
	if label == false then return end
	local text
	if field:sub(1, 2) == "g_" or field == "lv_vendor" then
		text = (amount < 0 and "-" or "+") .. ns.FormatMoney(math.abs(amount)) .. " " .. L[label]
	else
		text = (amount < 0 and "" or "+") .. ns.FormatNumber(amount) .. " " .. L[label or field]
	end
	log[#log + 1] = date("%H:%M:%S") .. "  " .. text
	if #log > LOG_MAX then table.remove(log, 1) end
end)

function T.PrintLog()
	if #log == 0 then
		ns.Print(L["Nothing tracked yet this session."])
		return
	end
	ns.Print(string.format(L["Last %d tracked changes:"], math.min(#log, 25)))
	for i = math.max(1, #log - 24), #log do print("  " .. log[i]) end
end

---------------------------------------------------------------------------
-- Self-test
---------------------------------------------------------------------------
function T.SelfTest()
	local results = {}
	local function check(name, ok, detail, warnOnly)
		results[#results + 1] = { name = name, state = ok and "PASS" or (warnOnly and "WARN" or "FAIL"), detail = detail }
	end
	local _, _, _, toc = GetBuildInfo()
	check(L["Client interface"], toc == 16001 or (toc and toc >= 16001), tostring(toc), true)
	check(L["Saved data loaded"], ns.db and ns.db.schema == 2, ns.db and ("schema " .. tostring(ns.db.schema)) or "nil")
	check(L["Guild detected"], ns.gkey ~= nil, tostring(ns.gkey))
	check(L["Guild roster readable"], not IsInGuild() or ns.rosterReady,
		string.format("%d/%d", ns.rosterCount or 0, GetNumGuildMembers() or 0) .. (ns.rosterComplete and "" or " (incomplete)"), true)
	check(L["Realm calendar"], C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime ~= nil, ns.Today())
	check(L["Addon messages"], C_ChatInfo and C_ChatInfo.SendAddonMessage ~= nil and C_ChatInfo.IsAddonMessagePrefixRegistered
		and C_ChatInfo.IsAddonMessagePrefixRegistered(ns.PREFIX), ns.PREFIX)
	local dmgType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone
	local v, why = ns.Tracker.MeterLocalTotal(dmgType)
	check(L["Damage meter readable (out of combat)"], type(v) == "number", why or tostring(v), true)
	check(L["XP readable"], ns.Readable(UnitXP("player")), tostring(UnitXP("player")))
	check(L["Money readable"], ns.Readable(GetMoney()), "")
	for _, gs in ipairs({ "COMBATLOG_XPGAIN_FIRSTPERSON", "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }) do
		check(L["Game text"] .. " " .. gs, type(_G[gs]) == "string", "", true)
	end
	local gatherNames = 0
	for _ in pairs(ns.Tracker.GATHER_SPELLS) do gatherNames = gatherNames + 1 end
	check(L["Gathering spells known"], gatherNames > 3, tostring(gatherNames), true)
	local missing = {}
	for ev in pairs(ns.unsupportedEvents) do missing[#missing + 1] = ev end
	check(L["All game events available"], #missing == 0, table.concat(missing, ", "), true)
	check(L["Price source (optional)"], ns.PriceSourceName() ~= nil, ns.PriceSourceName() or L["vendor prices only"], true)

	local colors = { PASS = "|cff40ff40", WARN = "|cffffcc00", FAIL = "|cffff4040" }
	local fails, warns = 0, 0
	ns.Print(L["Self-test:"])
	for _, r in ipairs(results) do
		if r.state == "FAIL" then fails = fails + 1 elseif r.state == "WARN" then warns = warns + 1 end
		print(string.format("  %s%s|r  %s%s", colors[r.state], r.state, r.name, (r.detail and r.detail ~= "") and (" |cff999999(" .. r.detail .. ")|r") or ""))
	end
	ns.Print(string.format(L["%d checks: %d failed, %d warnings."], #results, fails, warns))
	return results, fails, warns
end

---------------------------------------------------------------------------
-- Demo data
---------------------------------------------------------------------------
local DEMO_KEY = "~demo"
local DEMO_NAMES = {
	{ "Aldric", "WARRIOR", 60 }, { "Brina", "PRIEST", 58 }, { "Corvin", "MAGE", 52 }, { "Dalia", "ROGUE", 47 },
	{ "Eldon", "HUNTER", 44 }, { "Fenna", "DRUID", 39 }, { "Garrick", "PALADIN", 36 }, { "Hilde", "WARLOCK", 31 },
	{ "Ivo", "SHAMAN", 27 }, { "Jessa", "MAGE", 22 }, { "Korin", "WARRIOR", 18 }, { "Lyra", "PRIEST", 12 },
}

-- Small deterministic random generator, so the demo looks the same each time
local function Rand(seed)
	local s = seed
	return function(lo, hi)
		s = (s * 16807) % 2147483647 -- Park-Miller; exact in Lua 5.1 doubles
		return lo + (s % (hi - lo + 1))
	end
end

function T.Demo(on)
	if on == false then
		ns.db.guilds[DEMO_KEY] = nil
		if ns.db.view.guild == DEMO_KEY then ns.db.view.guild = nil end
		ns.Print(L["Demo data removed."])
		ns.MarkChanged()
		return
	end
	local g = ns.NewGuild(L["Demo Guild (sample data)"], "Demo", nil)
	g.demo = true
	g.rules.challengeMetric, g.rules.challengePrize = "quests", "100g"
	g.rules.goalMetric, g.rules.goalTarget = "gold", 2500 * 10000
	local rnd = Rand(42)
	local today = ns.Today()
	for i, info in ipairs(DEMO_NAMES) do
		local key = info[1]
		local p = ns.GetPlayer(g, key, true)
		p.class, p.level, p.version = info[2], info[3], ns.VERSION
		local skill = 13 - i
		for d = 0, 41 do
			if rnd(1, 10) <= 6 then
				local day = ns.ShiftDay(today, -d)
				local secs = rnd(1200, 10800)
				local h = secs / 3600
				local b = {
					playtime = secs, g_loot = math.floor(h * rnd(20000, 40000 + skill * 6000)),
					g_quest = math.floor(h * rnd(5000, 30000)), g_vendor = math.floor(h * rnd(0, 20000)),
					xp = info[3] < 60 and math.floor(h * rnd(15000, 30000 + skill * 3000)) or 0,
					mlevels = info[3] < 60 and math.floor(h * rnd(150, 400 + skill * 40)) or 0,
					damage = info[2] ~= "PRIEST" and math.floor(h * rnd(300000, 600000 + skill * 60000)) or math.floor(h * rnd(50000, 150000)),
					healing = (info[2] == "PRIEST" or info[2] == "DRUID" or info[2] == "SHAMAN" or info[2] == "PALADIN")
						and math.floor(h * rnd(200000, 800000)) or 0,
					kills = math.floor(h * rnd(40, 120 + skill * 8)), quests = math.floor(h * rnd(2, 8 + skill)),
					deaths = rnd(0, 3), bosses = rnd(0, 3), dungeons = rnd(0, 1), gathers = math.floor(h * rnd(0, 40)),
					crafts = rnd(0, 10), lv_vendor = math.floor(h * rnd(5000, 40000)), lv_auction = math.floor(h * rnd(10000, 120000)),
				}
				p.days[day] = b
				for k, v in pairs(b) do p.all[k] = (p.all[k] or 0) + v end
			end
		end
	end
	ns.db.guilds[DEMO_KEY] = g
	ns.Hall.Update(g)
	ns.db.view.guild = DEMO_KEY
	ns.Print(L["Demo data added. Switch guilds at the top of the window; '/granks demo off' removes it."])
	ns.UI.Show("list") -- (Toggle would close an already open window)
	ns.MarkChanged()
end
