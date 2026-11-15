-- Guild score, boards and the Discord text

-- One client whose guild contains the given players (data inserted directly)
local function GuildWith(players, rules)
	local w = NewWorld()
	w:AddGuild("Froga", "1")
	local c = w:NewClient({ name = "Viewer", guild = "Froga", rank = 0 })
	c:Login()
	local g = c:G()
	g.players = {}
	for key, b in pairs(players) do
		local p = c.ns.GetPlayer(g, key .. "-Firemaw", true)
		p.class, p.level = b.class or "WARRIOR", b.level or 30
		w:AddRosterMember("Froga", key .. "-Firemaw", 4, p.level, p.class)
		b.class, b.level = nil, nil
		p.days[c.ns.Today()] = b
	end
	c.ns.ReadRoster()
	for k, v in pairs(rules or {}) do g.rules[k] = v end
	return c, g, w
end

test("placement: best gets 100, zeros get 0, ties share, fewest deaths wins", function()
	local c, g = GuildWith({
		A = { playtime = 3600, g_loot = 30000, deaths = 0 },
		B = { playtime = 3600, g_loot = 20000, deaths = 2 },
		C = { playtime = 3600, g_loot = 20000, deaths = 5 },
		D = { playtime = 3600, deaths = 1 },
	})
	local scores = c.ns.ComputeScores(g, "week", 0)
	local by = {}
	for _, e in ipairs(scores) do by[e.name] = e end
	near(by.A.cats.gold, 100, 0.01, "best gold")
	near(by.B.cats.gold, 50, 0.01, "tie shares places 2-3 of 3 positive")
	near(by.C.cats.gold, 50, 0.01, "tie")
	near(by.D.cats.gold, 0, 0.01, "no gold = 0")
	near(by.A.cats.deaths, 100, 0.01, "no deaths best")
	near(by.C.cats.deaths, 0, 0.01, "most deaths worst")
	eq(scores[1].name, "A", "A is top")
end)

test("healers are ranked on healing in the combat category", function()
	local c, g = GuildWith({
		Tank = { playtime = 3600, damage = 900000 },
		Dps = { playtime = 3600, damage = 1200000 },
		Healer = { playtime = 3600, damage = 50000, healing = 1500000 },
	})
	local by = {}
	for _, e in ipairs(c.ns.ComputeScores(g, "week", 0)) do by[e.name] = e end
	near(by.Healer.cats.combat, 100, 0.01, "healer gets full combat score")
	near(by.Dps.cats.combat, 100, 0.01, "top dps too")
end)

test("minimum play time and level ranges decide who is ranked", function()
	local c, g = GuildWith({
		Quick = { playtime = 600, g_loot = 999999, level = 60 },
		Low = { playtime = 3600, g_loot = 10000, level = 15 },
		High = { playtime = 3600, g_loot = 20000, level = 60 },
	})
	local rows, unranked = c.ns.BuildBoard(g, "gold", "week", true, 0)
	eq(#rows, 2, "Quick is under 30 minutes")
	eq(unranked, 1, "one unranked")
	local brackets = c.ns.Brackets()
	local top = brackets[#brackets].value
	rows = c.ns.BuildBoard(g, "gold", "week", true, top)
	eq(#rows, 1, "only level 60 in the 60 bracket")
	eq(rows[1].name, "High", "High in 60 bracket")
	-- totals mode ranks Quick (no minimum for totals)
	rows = c.ns.BuildBoard(g, "gold", "week", false, 0)
	eq(rows[1].name, "Quick", "totals mode")
end)

test("gold source rules and loot value source change the numbers", function()
	local c, g = GuildWith({ A = { playtime = 3600, g_loot = 100, g_mail = 1000, lv_vendor = 5, lv_auction = 50 } })
	local b = g.players["A-Firemaw"].days[c.ns.Today()]
	eq(c.ns.MetricTotal(b, "gold", g), 1100, "all sources")
	g.rules.gold.mail = false
	eq(c.ns.MetricTotal(b, "gold", g), 100, "mail excluded")
	eq(c.ns.MetricTotal(b, "loot", g), 5, "vendor value")
	g.rules.itemValue = "auction"
	eq(c.ns.MetricTotal(b, "loot", g), 50, "auction value")
end)

test("Discord text: no empty rankings, challenge and goal lines, under Discord's limit (fix)", function()
	local players = {}
	for i = 1, 40 do
		players["Player" .. i] = { playtime = 3600 + i * 60, g_loot = 1000 * i, xp = 500 * i, kills = i, quests = i % 7 }
	end
	local c, g = GuildWith(players, { challengeMetric = "quests", challengePrize = "100g", goalMetric = "gold", goalTarget = 1000000 })
	local chunks = c.ns.BuildDiscordText(g, "week")
	local all = table.concat(chunks, "\n")
	for _, chunk in ipairs(chunks) do ok(#chunk <= 1900, "chunk under limit") end
	absent(all, "Deaths/h", "nobody died: no deaths line")
	absent(all, "Healing", "nobody healed: no healing line")
	contains(all, "Challenge leader", "challenge line")
	contains(all, "prize: 100g", "prize")
	contains(all, "Guild goal", "goal line")
	contains(all, "Leading", "leader line")
	-- last week wording
	local last = table.concat(c.ns.BuildDiscordText(g, "lastweek"), "\n")
	contains(last, "Nobody qualified yet", "empty last week")
end)

test("mail excluded by the guild's gold rules; short sessions not ranked", function()
	local players = {
		Ann = { playtime = 7200, g_loot = 120000, g_mail = 500000, xp = 90000, mlevels = 900, damage = 3000000, kills = 300, quests = 8, deaths = 1, bosses = 2, dungeons = 1, gathers = 5, crafts = 2, lv_vendor = 1000, lv_auction = 9000 },
		Bob = { playtime = 5400, g_loot = 80000, xp = 120000, mlevels = 1800, damage = 2000000, healing = 400000, kills = 250, quests = 20, deaths = 3 },
		Cid = { playtime = 3600, g_loot = 30000, xp = 20000, mlevels = 300, healing = 900000, kills = 40, quests = 3, deaths = 0, gathers = 40 },
		Dee = { playtime = 1200, g_loot = 999999 },
		Eve = { playtime = 4000, g_quest = 50000, xp = 70000, mlevels = 700, damage = 2600000, kills = 260, quests = 10, deaths = 3, bosses = 1, crafts = 12 },
	}
	local c, g = GuildWith(players)
	g.rules.gold.mail = false
	local lastWeekDay = c.ns.ShiftDay(c.ns.WeekStart(g), -3)
	for _, p in pairs(g.players) do p.days[lastWeekDay] = p.days[c.ns.Today()] end
	local scores = c.ns.ComputeScores(g, "lastweek", 0)
	eq(#scores, 4, "Dee under minimum")
	local byKey = {}
	for _, e in ipairs(scores) do byKey[e.name] = e.score end
	eq(byKey.Ann, 65, "Ann")
	eq(byKey.Eve, 65, "Eve")
	eq(byKey.Bob, 54, "Bob")
	eq(byKey.Cid, 50, "Cid (mail gold not counted for Ann)")
end)
