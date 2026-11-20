-- WoW: Forever names: the realm part changes between messages and sessions, and guildmates
-- see a longer name than UnitName gives you ("Healya Jamie" vs "Healya").
local SHARDS = { "CAMWOWEU4Realm6PvP", "CAMWOWEU5Realm4PvP", "CAMWOWEU5Realm6PvP", "CAMWOWEU4Realm4PvP" }

local function ForeverGuild(opts)
	local w = NewWorld()
	w.shards = SHARDS
	w.noRosterGUID = opts and opts.noRosterGUID
	w:AddGuild("Froga", "215999042")
	local healya = w:NewClient({ name = "Healya", surname = "Jamie", guild = "Froga", rank = 1, level = 55, class = "PRIEST", realm = SHARDS[1] })
	local joe = w:NewClient({ name = "Joe", surname = "Mario", guild = "Froga", rank = 3, level = 55, class = "WARRIOR", realm = SHARDS[2] })
	local kucca = w:NewClient({ name = "Kucca", surname = "Fiv", guild = "Froga", rank = 3, level = 33, class = "HUNTER", realm = SHARDS[3] })
	return w, healya, joe, kucca
end

local function Keys(g)
	local list = {}
	for key in pairs(g.players) do list[#list + 1] = key end
	table.sort(list)
	return table.concat(list, ", ")
end

local function Play(c, gold)
	c:Fire("LOOT_OPENED"); c:GainMoney(gold); c:Fire("LOOT_CLOSED")
end

test("Forever: each guildmate is stored once, whatever realm their messages show", function()
	local w, healya, joe, kucca = ForeverGuild()
	healya:Login(); joe:Login(); kucca:Login()
	w:Advance(30)
	for _, c in ipairs({ healya, joe, kucca }) do Play(c, 50000) end
	for _ = 1, 6 do w:Advance(400); healya.ns.Comm.SyncNow(); joe.ns.Comm.SyncNow() end
	eq(healya.ns.me, "Healya Jamie", "learned the name guildmates see (from the roster)")
	eq(healya.ns.gkey, "Froga", "guild key without the realm")
	for _, c in ipairs({ healya, joe, kucca }) do
		eq(Keys(c:G()), "Healya Jamie, Joe Mario, Kucca Fiv", c.name .. " stores each player once")
	end
	local rows = healya.ns.BuildBoard(healya:G(), "gold", "week", false, 0)
	eq(#rows, 3, "three rows, no duplicates")
end)

test("Forever: your own name is learned from your messages when the roster has no IDs", function()
	local w, healya, joe = ForeverGuild({ noRosterGUID = true })
	healya:Login(); joe:Login()
	eq(healya.ns.me, "Healya", "only the short name at first")
	w:Advance(30)
	Play(healya, 50000)
	w:Advance(400); healya.ns.Comm.SyncNow(); w:Advance(30)
	eq(healya.ns.me, "Healya Jamie", "renamed when our own message came back")
	eq(Keys(healya:G()), "Healya Jamie, Joe Mario", "own data moved, no 'Healya' left over")
	ok(healya.ns.db.chars["Healya Jamie"], "personal data moved too")
	eq(healya.ns.db.myNames[healya.guid], "Healya Jamie", "remembered for next login")
	healya:Logout(); healya:Login(); w:Advance(5)
	eq(healya.ns.me, "Healya Jamie", "right name straight away at the next login")
end)

test("Forever: the weekly popup recognises you as #1 (fix)", function()
	local w, healya, joe = ForeverGuild()
	healya:Login(); joe:Login()
	w:Advance(30)
	local ns, g = healya.ns, healya:G()
	local lastWeek = ns.ShiftDay(ns.WeekStart(g), -3)
	ns.GetPlayer(g, "Healya Jamie", true).days[lastWeek] = { playtime = 7200, g_loot = 900000, xp = 90000, quests = 20, kills = 100 }
	ns.GetPlayer(g, "Joe Mario", true).days[lastWeek] = { playtime = 7200, g_loot = 100000, xp = 10000, quests = 2, kills = 10 }
	ns.GetPlayer(g, "Kucca Fiv", true).days[lastWeek] = { playtime = 7200, g_loot = 50000, xp = 5000, quests = 1, kills = 5 }
	ok(ns.Alerts.ShowWeeklyPopup(g), "popup shown")
	local text = ns.Alerts.WeeklyPopupText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	contains(text, "1. Healya Jamie MVP", "you're on the podium")
	contains(text, "You finished #1 of 3", "and recognised as you")
	absent(text, "weren't ranked", "not 'you weren't ranked'")
end)

test("Forever: an older save with duplicates is merged once (pattern from a real save file)", function()
	local function day(play, gold) return { playtime = play, g_loot = gold, xp = gold, quests = 1 } end
	local saved = {
		guilds = {
			["Froga-CAMWOWEU5Realm6PvP"] = { name = "Froga", realm = "CAMWOWEU5Realm6PvP", clubId = "215999042",
				rules = { version = 1794770726, by = "Kecu", resetDay = 4, minMinutes = 30, gold = {}, excluded = { ["Cheat Er-CAMWOWEU4Realm4PvP"] = true } },
				hidden = {}, popupWeek = "2026-11-18",
				players = {
					["Healya-CAMWOWEU4Realm6PvP"] = { days = { ["2026-11-19"] = day(29300, 432746), ["2026-11-17"] = day(38818, 500089) }, all = { playtime = 100 }, level = 55, seen = 3 },
					["Healya Jamie-CAMWOWEU4Realm4PvP"] = { days = { ["2026-11-17"] = day(27226, 354677) }, all = {}, level = 51 },
					["Healya Jamie-CAMWOWEU5Realm4PvP"] = { days = { ["2026-11-19"] = day(9827, 188494), ["2026-11-15"] = day(12036, 166299) }, all = {}, level = 54 },
					["Kucca Fiv-CAMWOWEU4Realm6PvP"] = { days = { ["2026-11-18"] = day(18003, 13446) }, all = {}, level = 33, class = "HUNTER", seen = 2 },
					["Kucca Fiv-CAMWOWEU5Realm4PvP"] = { days = { ["2026-11-18"] = day(15300, 13446) }, all = {}, level = 32 },
					["Kucca Fiv-CAMWOWEU5Realm6PvP"] = { days = { ["2026-11-19"] = day(3297, 163) }, all = {}, level = 33 },
				},
			},
			["Froga-CAMWOWEU4Realm6PvP"] = { name = "Froga", realm = "CAMWOWEU4Realm6PvP", clubId = "215999042",
				rules = { version = 0, gold = {}, excluded = {} }, hidden = {},
				players = { ["Healya-CAMWOWEU4Realm6PvP"] = { days = {}, all = {}, level = 49, seen = 1 } } },
			["~solo-CAMWOWEU4Realm6PvP"] = { name = "No guild", realm = "CAMWOWEU4Realm6PvP", solo = true,
				rules = { version = 0, gold = {}, excluded = {} }, hidden = {},
				players = { ["Kahk-CAMWOWEU4Realm6PvP"] = { days = { ["2026-11-19"] = day(600, 10) }, all = {} } } },
		},
		chars = {
			["Healya-CAMWOWEU4Realm6PvP"] = { guild = "Froga-CAMWOWEU5Realm6PvP", personal = { rival = "Kucca Fiv-CAMWOWEU4Realm6PvP", records = {}, goals = {} } },
			["Kahk-CAMWOWEU4Realm6PvP"] = { guild = "~solo-CAMWOWEU4Realm6PvP" },
		},
		view = { guild = "Froga-CAMWOWEU5Realm6PvP" },
	}
	local w = NewWorld()
	w.shards = SHARDS
	w:AddGuild("Froga", "215999042")
	local healya = w:NewClient({ name = "Healya", surname = "Jamie", guild = "Froga", rank = 1, level = 55, class = "PRIEST", realm = SHARDS[1], saved = saved })
	healya:Login()
	w:Advance(10)
	local db = healya.ns.db
	local gkeys = {}
	for key in pairs(db.guilds) do gkeys[#gkeys + 1] = key end
	table.sort(gkeys)
	eq(table.concat(gkeys, ", "), "Froga, ~solo", "one Froga, one solo entry")
	local g = db.guilds.Froga
	eq(g.rules.version, 1794770726, "the saved rules won")
	ok(g.rules.excluded["Cheat Er"], "exclusions renamed")
	eq(Keys(g), "Healya Jamie, Kucca Fiv", "each player once; your short name merged into your full name")
	local me = g.players["Healya Jamie"]
	eq(me.days["2026-11-19"].playtime, 29300, "the most complete copy of each day kept")
	eq(me.days["2026-11-17"].playtime, 38818, "your own record beat the relayed copy")
	eq(me.days["2026-11-15"].playtime, 12036, "a day only a copy had is kept")
	eq(g.players["Kucca Fiv"].days["2026-11-18"].playtime, 18003, "largest copy of Kucca's day")
	eq(g.players["Kucca Fiv"].class, "HUNTER", "class kept")
	ok(db.chars["Healya Jamie"], "your personal data moved to your full name")
	eq(db.chars["Healya Jamie"].personal.rival, "Kucca Fiv", "rival renamed")
	ok(db.chars["Kahk"], "alt kept")
	eq(db.chars["Kahk"].guild, "~solo", "alt's guild key updated")
	ok(db.guilds["~solo"].players["Kahk"], "solo data kept")
	eq(healya.ns.gkey, "Froga", "back in the merged guild")
end)

test("Forever: two roster members with the same name are flagged in diagnostics", function()
	local w, healya = ForeverGuild()
	w:AddRosterMember("Froga", "Joe Mario-" .. SHARDS[4], 4, 20, "MAGE")
	w:AddRosterMember("Froga", "Joe Mario-" .. SHARDS[3], 4, 30, "ROGUE")
	healya:Login()
	w:Advance(10)
	healya.ns.ReadRoster()
	ok(healya.ns.nameClashes["Joe Mario"], "same name noticed")
	local before = #healya.printed
	healya:Slash("diag")
	local found = false
	for i = before + 1, #healya.printed do if healya.printed[i]:find("Joe Mario", 1, true) and healya.printed[i]:find("same name", 1, true) then found = true end end
	ok(found, "/granks diag mentions it")
end)
