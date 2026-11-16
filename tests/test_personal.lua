-- Personal features: personal bests, goals, weekly titles, rival, session recap, Me tab

local function Toasts(c, part)
	local n = 0
	for _, line in ipairs(c.printed) do if line:find(part, 1, true) then n = n + 1 end end
	return n
end

local function Loot(c, copper)
	c:Fire("LOOT_OPENED"); c:GainMoney(copper); c:Fire("LOOT_CLOSED")
end

-- Kurt/Sean/Maria with last week's data on Sean's side: Kurt best at everything, Maria last
local function LastWeekGuild()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login()
	local g, ns = sean:G(), sean.ns
	local d = ns.ShiftDay(ns.WeekStart(g), -3)
	local function day(key, mult)
		local p = ns.GetPlayer(g, key, true)
		p.days[d] = { playtime = 3600, g_loot = 10000 * mult, xp = 1000 * mult, mlevels = 100 * mult, damage = 50000 * mult,
			kills = 10 * mult, quests = mult, deaths = 3 - mult, bosses = mult, gathers = mult, crafts = mult }
	end
	day(kurt.key, 3); day(sean.key, 2); day(maria.key, 1)
	ns.Personal.ClearTitleCache()
	return w, kurt, sean, maria, g
end

test("personal bests: filled silently at first, a toast when you beat one (once)", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo" })
	c:Login()
	local ns = c.ns
	local yesterday = ns.ShiftDay(ns.Today(), -1)
	SeedDay(c, yesterday, { playtime = 3600, g_loot = 10000, quests = 3, xp = 1000 })
	ns.Personal.SeedRecords()
	local rec = ns.Personal.Data().records
	eq(rec.gold.value, 10000, "seeded from yesterday")
	eq(rec.gold.day, yesterday, "with its day")
	c.printed = {}
	Loot(c, 15000)
	ns.Personal.CheckRecords()
	eq(Toasts(c, "New personal best! Gold in a day"), 1, "toast for the new best")
	Loot(c, 5000)
	ns.Personal.CheckRecords()
	eq(Toasts(c, "New personal best! Gold in a day"), 1, "only once a day")
	eq(rec.gold.value, 20000, "record follows today's total")
	eq(rec.gold.day, ns.Today(), "dated today")
	ok(ns.Personal.CurrentSession().bests[1], "noted in this session's recap")
end)

test("days in a row: today counts once you've played, otherwise up to yesterday", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo" })
	c:Login({ settle = 1 })
	local ns = c.ns
	local today = ns.Today()
	SeedDay(c, ns.ShiftDay(today, -3), { playtime = 600 })
	SeedDay(c, ns.ShiftDay(today, -2), { playtime = 600 })
	SeedDay(c, ns.ShiftDay(today, -1), { playtime = 600 })
	ns.GetPlayer(c:G(), c.key).days[today] = nil
	eq(ns.Personal.Streak(), 3, "3 days up to yesterday")
	SeedDay(c, today, { playtime = 600 })
	eq(ns.Personal.Streak(), 4, "today makes 4")
end)

test("goals: progress, pace, a toast when reached (once), level goals and a limit of 3", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo", level = 30 })
	c:Login()
	local P = c.ns.Personal
	ok(P.AddGoal("gold", 5, "week"), "5 gold this week")
	ok(not P.AddGoal("level", 30), "can't target your current level")
	ok(P.AddGoal("level", 32), "reach level 32")
	local goals = P.Data().goals
	eq(P.GoalLabel(goals[1]):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "5g 0s this week", "label")
	eq(P.GoalLabel(goals[2]), "Reach level 32", "level label")
	local _, frac, status, done = P.GoalProgress(goals[1])
	eq(done, false, "not yet")
	contains(status, "behind", "behind at the start? no gold yet")
	c.printed = {}
	Loot(c, 30000)
	_, frac, status, done = P.GoalProgress(goals[1])
	eq(frac, 0.6, "60%")
	Loot(c, 30000)
	P.CheckGoals(); P.CheckGoals()
	eq(Toasts(c, "Goal reached"), 1, "one toast")
	ok(P.AddGoal("quests", 10, "month"), "third goal")
	ok(not P.AddGoal("kills", 10, "week"), "no fourth goal")
	P.RemoveGoal(1)
	eq(#goals, 2, "removed")
end)

test("weekly titles: #1 last week earns one; others see the title you show, but can't fake one", function()
	local w, kurt, sean, maria, g = LastWeekGuild()
	local P = sean.ns.Personal
	local codes = {}
	for _, t in ipairs(P.TitlesFor(g, kurt.key)) do codes[t.code] = true end
	ok(codes.gold and codes.quests and codes.mvp, "Kurt: Gold Baron, Quest Machine, MVP")
	eq(#P.TitlesFor(g, maria.key), 0, "Maria: none")
	-- Kurt shows Gold Baron; Sean sees it
	kurt.ns.Personal.SetTitle("gold")
	w:Advance(30)
	eq(g.players[kurt.key].title, "gold", "title arrived")
	eq(P.ShownTitle(g, kurt.key).name, "Gold Baron", "shown on Sean's side")
	-- Maria claims a title she didn't earn
	maria:Login()
	maria.ns.Personal.SetTitle("gold")
	w:Advance(30)
	eq(g.players[maria.key].title, "gold", "claim arrived")
	eq(P.ShownTitle(g, maria.key), nil, "but isn't shown: she didn't earn it")
	-- clearing it
	kurt.ns.Personal.SetTitle(nil)
	w:Advance(30)
	eq(P.ShownTitle(g, kurt.key), nil, "hidden again")
end)

test("rival: head to head, and an alert when you pass them", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	local g, ns = sean:G(), sean.ns
	local P = ns.Personal
	local today = ns.Today()
	ns.GetPlayer(g, kurt.key, true).days[today] = { playtime = 3600, g_loot = 50000, xp = 9000, quests = 5, kills = 20 }
	ns.GetPlayer(g, sean.key, true).days[today] = { playtime = 3600, g_loot = 20000, xp = 1000, quests = 2, kills = 5 }
	P.SetRival(kurt.key)
	local rows = P.HeadToHead(g, "week")
	eq(#rows, 5, "five stats")
	eq(rows[2].label, "Gold/h", "gold per hour row")
	ok(rows[2].theirs > rows[2].mine, "Kurt ahead in gold/h")
	sean.printed = {}
	P.CheckRival()
	eq(Toasts(sean, "rival"), 0, "first look: no alert")
	ns.GetPlayer(g, sean.key).days[today].g_loot = 90000
	P.CheckRival()
	eq(Toasts(sean, "You passed your rival Kurt in Gold/h"), 1, "alert when passing")
	P.CheckRival()
	eq(Toasts(sean, "You passed your rival Kurt"), 1, "only once")
	P.SetRival(nil)
	eq(#P.HeadToHead(g, "week"), 0, "no rival, no table")
end)

test("session recap: shown at the next login, not after a /reload", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo" })
	c:Login()
	Loot(c, 32000)
	c:GainXP(5000)
	w:Advance(600)
	c:Logout()
	-- /reload: same session continues, no recap
	c:Login({ reload = true })
	w:Advance(15)
	eq(c.ns.MeView.RecapText(), nil, "no recap after a reload")
	local cur = c.ns.Personal.CurrentSession()
	ok((cur.totals.playtime or 0) >= 590, "session time carried over")
	eq(c.ns.Personal.Value(cur.totals, "gold"), 32000, "session gold carried over")
	c:Logout()
	-- real login later
	w:Advance(3600)
	c:Login()
	w:Advance(15)
	local text = c.ns.MeView.RecapText()
	ok(text, "recap shown")
	local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	contains(plain, "+3g 20s", "gold")
	contains(plain, "10m", "play time")
	-- /granks recap with no new play shows the last session again
	c:Slash("recap")
	ok(c.ns.MeView.RecapText(), "recap on demand")
end)

test("session recap: labelled sections, highlights and the guild chat line", function()
	local w = NewWorld()
	local c = w:NewClient({ name = "Solo" })
	c:Login()
	Loot(c, 32000)
	c:GainXP(5000)
	w:Advance(600)
	ok(c.ns.ShowRecap(), "recap opens for the current session")
	local plain = c.ns.MeView.RecapText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	contains(plain, "This session so far", "title")
	contains(plain, "played", "play time line")
	contains(plain, "Gold +3g 20s", "gold tile")
	contains(plain, "/h", "per hour rate")
	contains(plain, "Experience 5,000", "xp tile")
	for _, label in ipairs({ "Quests", "Kills", "Deaths", "Gathered", "Crafted", "Guild rank" }) do
		contains(plain, label, label .. " tile")
	end
	local chat = c.ns.MeView.RecapChat()
	ok(chat and #chat <= 255, "chat line fits one message")
	contains(chat, "3g 20s", "chat has gold")
	local d = c.ns.Personal.SessionDetails(c.ns.Personal.CurrentSession())
	eq(d.gold, 32000, "details: gold")
	eq(d.xp, 5000, "details: xp")
	eq(d.goldVs, nil, "no comparison when the week is just this session")
end)

test("Me tab: stats, chart, goal form, bests, rival and titles without errors", function()
	local w, kurt, sean, maria, g = LastWeekGuild()
	local ns = sean.ns
	ns.db.ui.welcomed = true
	SeedDay(sean, ns.Today(), { playtime = 3600, g_loot = 30000, xp = 4000, quests = 6 })
	sean:Slash("me")
	eq(ns.UI.Current(), "me", "Me tab open")
	local el = ns.MeView.Internals()
	contains(el.tiles[2].label:GetText(), "Gold/h", "gold per hour tile")
	contains(el.tiles[2].value:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "3g 0s", "3g per hour")
	for _, key in ipairs({ "today", "all", "week" }) do el.chips[key]:GetScript("OnClick")(el.chips[key]) end
	eq(ns.db.ui.mePeriod, "week", "period chips")
	-- add a goal through the form
	el.addGoal:GetScript("OnClick")(el.addGoal)
	ok(el.form:IsShown(), "form open")
	el.newGoal.kind, el.newGoal.period = "quests", "week"
	el.formTarget:SetText("20")
	el.formAdd:GetScript("OnClick")(el.formAdd)
	eq(#ns.Personal.Data().goals, 1, "goal added")
	ok(not el.form:IsShown(), "form closed")
	ok(el.goals[1].label:IsShown(), "goal row shown")
	-- rival from the player card
	ns.UI.Show("list")
	ns.Card.Show(kurt.key)
	ns.Personal.SetRival(kurt.key)
	ns.UI.Show("me")
	contains(el.rivalHead:GetText(), "Kurt", "rival shown")
	-- Sean holds no title (Kurt won everything): buttons can't be picked
	el.titles[2]:GetScript("OnClick")(el.titles[2])
	eq(ns.Personal.MyTitleCode(), nil, "unearned titles can't be shown")
	kurt.ns.db.ui.welcomed = true
	kurt.ns.UI.Show("me")
end)

test("you can't pick yourself or one of your alts as rival, however the name is written (fix)", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	local g, ns = sean:G(), sean.ns
	local P = ns.Personal
	ok(ns.SameCharacter("Sean-Firemaw", "sean-fire maw"), "same character, written differently")
	ok(not ns.SameCharacter("Sean-Firemaw", "Sean-Argent Dawn"), "different realm")
	eq(P.SetRival(sean.key), false, "not yourself")
	eq(P.SetRival("SEAN-firemaw"), false, "not yourself in other letters")
	eq(P.SetRival("Sean-Fire Maw"), false, "not yourself with the realm spelled differently")
	ns.GetPlayer(g, kurt.key, true).days[ns.Today()] = { playtime = 3600, g_loot = 500 }
	ns.db.chars["Seanalt-Firemaw"] = {}
	ns.GetPlayer(g, "Seanalt-Firemaw", true).days[ns.Today()] = { playtime = 3600, g_loot = 100 }
	ns.GetPlayer(g, "Sean-Fire Maw", true).days[ns.Today()] = { playtime = 3600, g_loot = 100 }
	eq(P.SetRival("Seanalt-Firemaw"), false, "not one of your alts")
	eq(P.Rival(), nil, "still no rival")
	eq(P.SetRival(kurt.key), true, "a guildmate is fine")
	eq(P.Rival(), kurt.key, "Kurt")
	-- a rival saved as yourself by an older version is cleared
	P.Data().rival = sean.key
	eq(P.Rival(), nil, "cleared")
	eq(P.Data().rival, nil, "and forgotten")
	-- the rival list in the Me tab leaves you and your alts out
	ns.db.ui.welcomed = true
	ns.UI.Show("me")
	local el = ns.MeView.Internals()
	local names = {}
	local root = { CreateRadio = function(_, text) names[#names + 1] = text end }
	el.rivalPick._menu(nil, root)
	local list = table.concat(names, ",")
	contains(list, "Kurt", "Kurt offered")
	absent(list, "Seanalt", "alt not offered")
	absent(list, "Sean,", "you aren't offered")
	ok(not list:find("Sean$"), "you aren't offered (end)")
end)

test("lead cards: gold card when you take #1, grey card when you lose it, once a day each", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	sean:Login() -- (Kurt stays offline so his real client doesn't sync over the numbers set here)
	local g, ns = sean:G(), sean.ns
	local A = ns.Alerts
	local today = ns.Today()
	ns.GetPlayer(g, kurt.key, true).days[today] = { playtime = 3600, g_loot = 50000 }
	ns.GetPlayer(g, sean.key, true).days[today] = { playtime = 3600, g_loot = 20000 }
	A.CheckLead("gold")
	eq(A.CardText(), nil, "first look: just remembers Kurt leads")
	ns.GetPlayer(g, sean.key).days[today].g_loot = 90000
	A.CheckLead("gold")
	local text = A.CardText()
	ok(text, "card shown")
	contains(text, "You're #1 in Gold earned per hour", "title")
	contains(text, "you passed Kurt", "who you passed")
	w:Advance(7)
	eq(A.CardText(), nil, "gone after a few seconds")
	-- Kurt takes it back: grey card
	ns.GetPlayer(g, kurt.key).days[today].g_loot = 200000
	A.CheckLead("gold")
	contains(A.CardText(), "Kurt took the lead in Gold earned per hour", "lost the lead")
	contains(A.CardText(), "You're #2", "your place")
	w:Advance(7)
	-- and again the same day: no second gold card
	ns.GetPlayer(g, sean.key).days[today].g_loot = 400000
	A.CheckLead("gold")
	eq(A.CardText(), nil, "once a day")
	-- ties: nobody leads alone
	ns.GetPlayer(g, kurt.key).days[today].g_loot = 400000
	A.CheckLead("gold")
	eq(A.CardText(), nil, "no card on a tie")
	-- off in settings
	ns.db.leadCards = false
	ns.GetPlayer(g, kurt.key).days[today].quests = 9
	ns.GetPlayer(g, sean.key).days[today].quests = 1
	A.CheckLead("quests")
	ns.GetPlayer(g, sean.key).days[today].quests = 20
	A.CheckLead("quests")
	eq(A.CardText(), nil, "no cards when switched off")
end)
