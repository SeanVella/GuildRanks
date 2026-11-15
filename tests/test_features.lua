-- Hall of Fame, session bar, alerts, weekly popup, announcements, version notice,
-- integrations, in-game tools and every window page

-- Kurt/Sean/Maria with N past weeks of data (Kurt always best, Maria always last)
local function GuildWithHistory(weeks)
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	sean:Login()
	local g = sean:G()
	local ns = sean.ns
	local start = ns.WeekStart(g)
	local function day(key, d, mult)
		local p = ns.GetPlayer(g, key, true)
		p.days[d] = { playtime = 3600, g_loot = 10000 * mult, xp = 1000 * mult, mlevels = 100 * mult, damage = 50000 * mult,
			kills = 10 * mult, quests = mult, deaths = 4 - mult, bosses = mult, gathers = mult, crafts = mult }
	end
	for wk = 1, weeks do
		local d = ns.ShiftDay(start, -7 * wk + 1)
		day(kurt.key, d, 3); day(sean.key, d, 2); day(maria.key, d, 1)
	end
	-- Sean topped one week (the oldest)
	if weeks >= 3 then
		local d = ns.ShiftDay(start, -7 * weeks + 1)
		day(sean.key, d, 4)
	end
	ns.GetPlayer(g, kurt.key).class = "WARRIOR"
	ns.GetPlayer(g, maria.key).class = "PRIEST"
	return w, kurt, sean, maria, g
end

test("Hall of Fame: weekly snapshots, MVP counts, badges, records, streaks and history", function()
	local w, kurt, sean, maria, g = GuildWithHistory(4)
	local ns = sean.ns
	ns.Hall.Update(g)
	local weeks = ns.Hall.Weeks(g)
	eq(#weeks, 4, "four finished weeks")
	eq(weeks[1].mvp, kurt.key, "Kurt MVP last week")
	eq(weeks[1].spoon, maria.key, "Maria last")
	eq(ns.Hall.MVPCount(g, kurt.key), 3, "Kurt MVP 3 times")
	eq(ns.Hall.MVPCount(g, sean.key), 1, "Sean once")
	contains(ns.Hall.Badge(g, kurt.key), "x3", "badge shows x3")
	eq(ns.Hall.Badge(g, maria.key), "", "no badge for Maria")
	local rec = ns.Hall.Records(g)
	eq(rec.mvps[1].key, kurt.key, "most MVPs")
	ok(#rec.best >= 5, "best week per ranking")
	ok(#rec.streaks >= 1 and rec.streaks[1].n == 4, "4-week top-3 streak")
	local hist = ns.Hall.History(g, sean.key, 6)
	eq(#hist, 4, "Sean's history")
	eq(hist[1].rank, 2, "Sean 2nd last week")
	eq(hist[4].rank, 1, "Sean 1st in the oldest week")
	local prevRank = ns.Hall.PreviousRank(g, sean.key, weeks[1].from)
	eq(prevRank, 2, "previous week rank")
	sean:Slash("hall")
	sean.ns.UI.Show("hall")
end)

test("snapshots survive after the daily data is pruned", function()
	local w, kurt, sean, maria, g = GuildWithHistory(2)
	sean.ns.Hall.Update(g)
	for _, p in pairs(g.players) do p.days = {} end
	sean.ns.Hall.Update(g)
	eq(#sean.ns.Hall.Weeks(g), 2, "still two weeks")
	eq(sean.ns.Hall.MVPCount(g, kurt.key), 2, "MVP count kept")
end)

test("weekly challenge leader/winner and guild goal progress", function()
	local w, kurt, sean, maria, g = GuildWithHistory(1)
	local ns = sean.ns
	g.rules.challengeMetric, g.rules.challengePrize = "quests", "100g"
	g.rules.goalMetric, g.rules.goalTarget = "gold", 100000
	local leader = ns.ChallengeLeader(g, "lastweek")
	eq(leader.key, kurt.key, "Kurt won the quest challenge")
	local cur, target = ns.GoalProgress(g, "lastweek")
	eq(cur, 60000, "combined gold last week")
	eq(target, 100000, "target")
	ns.Hall.Update(g)
	eq(ns.Hall.Weeks(g)[1].challenge.key, kurt.key, "winner saved in the Hall of Fame")
	sean:Slash("")
	sean.ns.UI.Show("list")
end)

test("session bar shows rank, gold/h, XP/h and time to level", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	sean.xp, sean.xpMax = 0, 100000
	sean:Login()
	sean:Slash("bar")
	ok(sean.ns.db.ui.bar.show, "bar on")
	sean:Fire("LOOT_OPENED"); sean:GainMoney(20000); sean:Fire("LOOT_CLOSED")
	sean:GainXP(10000)
	w:Advance(1800)
	local gph, xph, lph, toLevel = sean.ns.Bar.SessionStats()
	near(gph, 40000, 800, "gold per hour")
	near(xph, 20000, 400, "xp per hour")
	near(toLevel, 90000 / 20000 * 3600, 400, "time to level")
	local text = sean.ns.Bar.Text()
	contains(text, "#1/1", "rank")
	contains(text, "XP/h", "xp")
	sean:Slash("bar")
	ok(not sean.ns.db.ui.bar.show, "bar off")
end)

test("rank-change alert when someone passes you (once, throttled)", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	sean:Fire("LOOT_OPENED"); sean:GainMoney(50000); sean:Fire("LOOT_CLOSED")
	kurt:Fire("LOOT_OPENED"); kurt:GainMoney(10000); kurt:Fire("LOOT_CLOSED")
	w:Advance(1900) -- both qualify, Sean ahead in gold
	sean.ns.Alerts.CheckRanks() -- baseline
	local before = #sean.printed
	kurt:Fire("LOOT_OPENED"); kurt:GainMoney(200000); kurt:Fire("LOOT_CLOSED")
	w:Advance(320) -- Kurt's update arrives; the 60 s background check notices
	sean.ns.Alerts.CheckRanks()
	local found = false
	for i = before + 1, #sean.printed do
		if sean.printed[i]:find("Kurt just passed you in ", 1, true) then found = true end
	end
	ok(found, "alert shown")
	local count = 0
	for i = before + 1, #sean.printed do
		if sean.printed[i]:find("just passed you", 1, true) then count = count + 1 end
	end
	eq(count, 1, "shown once, not repeated")
end)

test("weekly popup appears once after the reset; MVP announced in guild chat exactly once", function()
	local w, kurt, sean, maria, g = GuildWithHistory(1)
	g.rules.announceMVP = true
	kurt:Login(); maria:Login()
	for _, c in ipairs({ kurt, maria }) do
		local cg = c:G()
		cg.rules.announceMVP = true
		for key, p in pairs(g.players) do cg.players[key] = sean.ns.Tools and W_DeepCopy and W_DeepCopy(p) or p end
	end
	for _, c in ipairs({ sean, kurt, maria }) do c.ns.Alerts.WeeklyCheck() end
	w:Advance(60)
	local announcements = 0
	for _, line in ipairs(w.chat) do
		if line.msg:find("last week's MVP is Kurt", 1, true) then announcements = announcements + 1 end
	end
	eq(announcements, 1, "one announcement for the whole guild")
	eq(g.popupWeek, sean.ns.WeekStart(g), "popup marked as shown")
	local lines = sean.ns.Alerts.WeeklySummaryLines(g)
	contains(table.concat(lines, "\n"), "You finished #2 of 3", "my place")
	-- second check the same week: nothing new
	local chatBefore = #w.chat
	sean.ns.Alerts.WeeklyCheck(); w:Advance(60)
	eq(#w.chat, chatBefore, "no second announcement")
end)

test("level-up announcement only when switched on", function()
	local w = NewWorld()
	local _, sean = StandardGuild(w)
	sean:Login()
	sean:Fire("PLAYER_LEVEL_UP", 35); w:Advance(2)
	eq(#w.chat, 0, "off by default")
	sean.ns.db.announceLevel = true
	sean:Fire("PLAYER_LEVEL_UP", 36); w:Advance(2)
	eq(#w.chat, 1, "announced")
	contains(w.chat[1].msg, "level 36", "message")
	sean.inInstance = true
	sean:Fire("PLAYER_LEVEL_UP", 37); w:Advance(2)
	eq(#w.chat, 1, "never inside instances")
end)

test("newer version used in the guild is noticed", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt.version = "1.2.0"
	kurt:Login(); sean:Login()
	w:Advance(90)
	eq(sean.ns.newerVersion, "1.2.0", "newer version noted")
	local said = false
	for _, l in ipairs(sean.printed) do if l:find("newer version", 1, true) then said = true end end
	ok(said, "told once")
	eq(kurt.ns.newerVersion, nil, "Kurt has the newest")
end)

test("integrations: TradeSkillMaster, then Auctionator prices; LibDataBroker + minimap button", function()
	local w = NewWorld()
	w:AddGuild("Froga", "1")
	local registered = {}
	local LDB = { NewDataObject = function(_, name, obj) registered.ldb = obj; return obj end }
	local Icon = { Register = function(_, name) registered.icon = name end, Hide = function() end, Show = function() end }
	local tsm = w:NewClient({ name = "Goblin", guild = "Froga", rank = 4, addons = {
		TSM_API = { ToItemString = function(link) return "i:" .. link:match("item:(%d+)") end,
			GetCustomPriceValue = function(src, item) return src == "dbmarket" and 5000 or nil end },
		LibStub = function(name) return ({ ["LibDataBroker-1.1"] = LDB, ["LibDBIcon-1.0"] = Icon })[name] end,
	} })
	local auc = w:NewClient({ name = "Trader", guild = "Froga", rank = 4, addons = {
		Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(caller, link) return 777 end } } },
	} })
	tsm:Login(); auc:Login()
	local loot = "You receive loot: |cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|rx2."
	tsm:Fire("CHAT_MSG_LOOT", loot); auc:Fire("CHAT_MSG_LOOT", loot)
	eq(tsm:Today().lv_auction, 10000, "TSM price")
	eq(auc:Today().lv_auction, 1554, "Auctionator price")
	eq(tsm:Today().lv_vendor, 200, "vendor price kept")
	eq(tsm.ns.PriceSourceName(), "TradeSkillMaster", "price source")
	ok(registered.ldb, "data broker object")
	eq(registered.icon, "GuildRanks", "minimap button")
	w:Advance(40)
	ok(registered.ldb.text, "broker text set")
end)

test("in-game tools: selftest passes, log records changes, demo data comes and goes", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	sean:Login()
	local results, fails = sean.ns.Tools.SelfTest()
	eq(fails, 0, "no failed checks")
	sean:Fire("QUEST_TURNED_IN", 1, 0, 500); sean:GainMoney(500)
	sean:Slash("log")
	local logged = false
	for _, l in ipairs(sean.printed) do if l:find("gold (quest)", 1, true) then logged = true end end
	ok(logged, "log shows quest gold")
	sean:Slash("demo")
	local demo = sean.ns.db.guilds["~demo"]
	ok(demo and demo.demo, "demo guild added")
	eq(sean.ns.db.view.guild, "~demo", "window shows demo")
	ok(#sean.ns.BuildBoard(demo, "score", "lastweek", false, 0) >= 8, "demo leaderboard filled")
	ok(#sean.ns.Hall.Weeks(demo) >= 3, "demo Hall of Fame filled")
	for _, view in ipairs({ "list", "members", "settings", "hall" }) do sean.ns.UI.Show(view) end
	sean:Slash("demo off")
	eq(sean.ns.db.guilds["~demo"], nil, "demo removed")
	sean:Slash("diag"); sean:Slash("weekly"); sean:Slash("help")
end)

test("old data from the removed Discord automation is deleted from the save file", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo", saved = { exportJSON = string.rep("x", 5000), exportAt = 1, exportError = "x" } })
	c:Login()
	eq(c.ns.db.exportJSON, nil, "export removed")
	eq(c.ns.db.exportAt, nil, "time removed")
	eq(c.ns.db.exportError, nil, "error removed")
end)

test("every window page opens for a guild, solo and another guild without errors", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	w:Advance(90)
	for _, view in ipairs({ "list", "members", "settings", "hall", "list" }) do sean.ns.UI.Show(view) end
	sean.ns.ShowDiscordCopy(sean:G(), "week")
	sean.ns.ShowDiscordPart(1)
	local loner = w:NewClient({ name = "Loner" })
	loner:Login()
	loner:Slash("")
	for _, view in ipairs({ "members", "settings", "hall", "list" }) do loner.ns.UI.Show(view) end
end)

test("big guild (300 members, 2 months): background work stays in small steps", function()
	local w = NewWorld()
	w:AddGuild("Big", "9")
	local me = w:NewClient({ name = "Me", guild = "Big", rank = 0 })
	me:Login()
	local ns, g = me.ns, me:G()
	math.randomseed(7)
	for i = 1, 300 do
		local key = "P" .. i .. "-Firemaw"
		w:AddRosterMember("Big", key, 4, math.random(10, 60), "MAGE")
		local p = ns.GetPlayer(g, key, true)
		p.level = math.random(10, 60)
		for d = 0, 61 do
			if math.random() < 0.6 then
				p.days[ns.ShiftDay(ns.Today(), -d)] = { playtime = math.random(600, 10000), g_loot = math.random(1, 90000),
					xp = math.random(1, 90000), damage = math.random(1, 2000000), kills = math.random(0, 300), quests = math.random(0, 20) }
			end
		end
	end
	ns.ReadRoster()
	local function ms(fn)
		local t = os.clock()
		fn()
		return (os.clock() - t) * 1000
	end
	-- generous limits: CI machines vary; the point is to catch big regressions
	ok(ms(function() ns.Alerts.CheckRanks("gold") end) < 60, "one ranking check is quick")
	ok(ms(function() ns.Hall.UpdateGradually(g) end) < 250, "one Hall of Fame step is quick")
	w:Advance(5) -- remaining steps run on timers
	ok(#ns.Hall.Weeks(g) >= 8, "all weeks built gradually")
	ok(ms(function() ns.BuildBoard(g, "score", "week", false, 0) end) < 120, "leaderboard refresh is quick")
end)
