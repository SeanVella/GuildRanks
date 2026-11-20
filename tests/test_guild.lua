-- Which guild you're in, alts in other guilds, same-name guilds, rosters

test("a character without a guild gets solo mode with their own stats", function()
	local w = NewWorld()
	local loner = w:NewClient({ name = "Loner" })
	loner:Login()
	eq(loner.ns.gkey, "~solo", "solo key")
	ok(loner:G().solo, "solo flag")
	loner:Fire("LOOT_OPENED"); loner:GainMoney(100); loner:Fire("LOOT_CLOSED")
	eq(loner:Today().g_loot, 100, "tracked")
	ok(loner.ns.CanEditRules(), "can set own rules")
	eq(loner.ns.Comm.QueueLength(), 0, "nothing to send")
end)

test("joining a guild switches to it; data stays per guild", function()
	local w = NewWorld()
	w:AddGuild("Froga", "1")
	local c = w:NewClient({ name = "Newbie" })
	c:Login()
	c:Fire("LOOT_OPENED"); c:GainMoney(100); c:Fire("LOOT_CLOSED")
	c.guild = "Froga"
	w.guilds.Froga.members[c.key] = { key = c.key, rankIndex = 4, rankName = "Initiate", level = 10, class = "WARRIOR", online = true, client = c }
	c:Fire("PLAYER_GUILD_UPDATE", "player")
	w:Advance(3)
	eq(c.ns.gkey, "Froga", "switched")
	c:Fire("LOOT_OPENED"); c:GainMoney(50); c:Fire("LOOT_CLOSED")
	eq(c:Today().g_loot, 50, "new guild has only the new gold")
	eq(c.ns.db.guilds["~solo"].players[c.key].days[c.ns.Today()].g_loot, 100, "solo data kept")
end)

test("alts in different guilds keep separate leaderboards in the same saved data", function()
	local w = NewWorld()
	w:AddGuild("Froga", "1"); w:AddGuild("Alts Club", "2")
	local main = w:NewClient({ name = "Sean", guild = "Froga", rank = 1 })
	main:Login()
	main:Fire("LOOT_OPENED"); main:GainMoney(1000); main:Fire("LOOT_CLOSED")
	w:Advance(5)
	main:Logout()
	local alt = w:NewClient({ name = "Seanalt", guild = "Alts Club", rank = 0, saved = main.saved })
	alt:Login()
	eq(alt.ns.gkey, "Alts Club", "alt's guild")
	ok(alt.ns.db.guilds["Froga"], "main's guild still saved")
	-- the window can show the other guild
	alt.ns.db.view.guild = "Froga"
	local g = alt.ns.V()
	eq(g.name, "Froga", "viewing main's guild")
	ok(not alt.ns.CanEditRules(g), "can't edit another guild's rules")
	alt:Slash("")
	alt.ns.UI.Show("members"); alt.ns.UI.Show("settings"); alt.ns.UI.Show("hall"); alt.ns.UI.Show("list")
end)

test("a new guild with the same name and realm doesn't inherit the old guild's data", function()
	local w = NewWorld()
	w:AddGuild("Froga", "111")
	local c = w:NewClient({ name = "Sean", guild = "Froga", rank = 1 })
	c:Login()
	c:Fire("LOOT_OPENED"); c:GainMoney(1000); c:Fire("LOOT_CLOSED")
	c:Logout()
	w.guilds.Froga.clubId = "222" -- guild disbanded and recreated with the same name
	c:Login()
	eq(c.ns.gkey, "Froga", "same key")
	eq(c:G().clubId, "222", "new guild")
	eq(c:Today().g_loot, nil, "starts empty")
	local archived = false
	for key, g in pairs(c.ns.db.guilds) do
		if key:find("Froga (", 1, true) then archived = g.players[c.key].days[c.ns.Today()].g_loot == 1000 end
	end
	ok(archived, "old data archived separately")
end)

test("players who left the guild drop off the board, but an incomplete roster hides nobody (fix)", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login(); maria:Login()
	for _, c in ipairs({ kurt, sean, maria }) do c:Fire("LOOT_OPENED"); c:GainMoney(500); c:Fire("LOOT_CLOSED") end
	w:Advance(120)
	eq(#sean.ns.BuildBoard(sean:G(), "gold", "week", false, 0), 3, "all three")
	-- Blizzard returns a partial roster: nobody may vanish
	w.partialRoster = true
	sean.ns.ReadRoster()
	ok(not sean.ns.rosterComplete, "roster marked incomplete")
	eq(#sean.ns.BuildBoard(sean:G(), "gold", "week", false, 0), 3, "still all three")
	-- Maria really leaves the guild
	w.partialRoster = false
	maria:Logout()
	w.guilds.Froga.members[maria.key] = nil
	sean.ns.ReadRoster()
	eq(#sean.ns.BuildBoard(sean:G(), "gold", "week", false, 0), 2, "Maria gone after leaving")
end)

test("members page lists who has the addon and who doesn't", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	w:AddRosterMember("Froga", "Nadia-Firemaw", 4, 50, "HUNTER")
	kurt:Login(); sean:Login()
	w:Advance(120)
	local missing = sean.ns.MembersWithoutAddon()
	local names = {}
	for _, m in ipairs(missing) do names[m.name] = true end
	ok(names.Nadia, "Nadia has no addon")
	ok(names.Maria, "Maria (never logged in) has no addon")
	ok(not names.Kurt, "Kurt has it")
end)
