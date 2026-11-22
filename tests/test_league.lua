-- Guild vs Guild: team sheets over the league channel, challenges, rivals, weekly results

local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function Printed(c, text)
	for _, line in ipairs(c.printed) do if Plain(line):find(text, 1, true) then return line end end
	return nil
end

local FROGA = { playtime = 3600, g_loot = 50000, mlevels = 1000, damage = 100000, quests = 5, kills = 20 }
local OWLS = { playtime = 3600, g_loot = 20000, mlevels = 1500, damage = 50000, healing = 30000, quests = 3, kills = 10, gathers = 4 }

-- Put this league week's stats for every listed member into a client's own save
local function Seed(c, keys, bucket)
	local g = c:G()
	for _, key in ipairs(keys) do
		local p = c.ns.GetPlayer(g, key, true)
		local b = {}
		for k, v in pairs(bucket) do b[k] = v end
		p.days[c.ns.Today()] = b
	end
end

local function TwoGuilds(w)
	local kurt, sean, maria = StandardGuild(w)
	w:AddGuild("Night Owls", "99887766")
	local ana = w:NewClient({ name = "Ana", guild = "Night Owls", rank = 0, level = 40, class = "PALADIN" })
	local bo = w:NewClient({ name = "Bo", guild = "Night Owls", rank = 3, level = 38, class = "HUNTER" })
	local cy = w:NewClient({ name = "Cy", guild = "Night Owls", rank = 3, level = 36, class = "DRUID" })
	-- AFK: live play time doesn't dilute the seeded per-hour numbers
	for _, c in ipairs({ kurt, sean, maria, ana, bo, cy }) do c.afk = true end
	return kurt, sean, maria, ana, bo, cy
end

local function SeedAll(froga, owls)
	for _, c in ipairs(froga) do Seed(c, { "Kurt", "Sean", "Maria" }, FROGA) end
	for _, c in ipairs(owls) do Seed(c, { "Ana", "Bo", "Cy" }, OWLS) end
end

-- Jump the clock forward (everyone idle: timers move with it, nothing catches up)
local function Jump(w, secs)
	w.now = w.now + secs
	w.epochNow = nil
	for _, t in ipairs(w.timers) do t.at = t.at + secs end
end

test("guild vs guild: guilds hear each other, an officer challenges, the other guild's officer accepts", function()
	local w = NewWorld()
	local kurt, sean, maria, ana, bo, cy = TwoGuilds(w)
	for _, c in ipairs({ kurt, sean, maria, ana, bo, cy }) do c:Login() end
	SeedAll({ kurt, sean, maria }, { ana, bo, cy })
	w:Advance(700)
	-- both guilds are on the hidden league channel and sent their team sheets
	local beacons = 0
	for _, s in ipairs(w.sent) do if s.chatType == "CHANNEL" and s.msg:find(";b;", 1, true) then beacons = beacons + 1 end end
	ok(beacons >= 2, "team sheets broadcast on the league channel")
	ok(sean.ns.League.TheirSheet("Night Owls"), "Froga knows Night Owls")
	ok(bo.ns.League.TheirSheet("Froga"), "Night Owls know Froga")
	-- no member names ever leave the guild
	for _, s in ipairs(w.sent) do
		if s.chatType ~= "GUILD" and s.msg:sub(1, 2) == "G;" then
			for _, name in ipairs({ "Kurt", "Sean", "Maria", "Ana", "Bo", "Cy" }) do
				ok(not s.msg:find(name, 1, true), "no names in league messages: " .. s.msg)
			end
		end
	end
	-- All guilds: both listed with a power score; only officers get the Challenge button
	sean.ns.db.ui.welcomed, maria.ns.db.ui.welcomed = true, true
	sean.ns.db.ui.leagueView, maria.ns.db.ui.leagueView = "all", "all"
	sean:Slash("league")
	local rows = sean.ns.UI.DirectoryTexts()
	eq(#rows, 2, "two guilds listed")
	local owlsRow
	for _, r in ipairs(rows) do if Plain(r):find("Night Owls", 1, true) then owlsRow = r end end
	ok(owlsRow and owlsRow:find("[Challenge]", 1, true), "officer can challenge Night Owls")
	maria:Slash("league")
	for _, r in ipairs(maria.ns.UI.DirectoryTexts()) do ok(not r:find("[Challenge]", 1, true), "members can't challenge") end
	eq(select(1, maria.ns.League.Challenge("Night Owls")), false, "member challenge refused")
	-- Sean challenges; Ana (officer) gets the popup, Bo (member) doesn't
	ok(sean.ns.UI.DirectoryChallenge("Night Owls"), "challenge clicked")
	w:Advance(10)
	contains(Plain(ana.ns.LeagueUI.InviteText() or ""), "<Froga> challenges your guild", "Ana sees the invite")
	eq(bo.ns.LeagueUI.InviteText(), nil, "no invite for members")
	ana.ns.LeagueUI.ClickInvite(true)
	w:Advance(15)
	for _, c in ipairs({ kurt, sean, maria }) do ok(c.ns.League.IsRival(c:G(), "Night Owls"), c.name .. ": Night Owls are rivals") end
	for _, c in ipairs({ ana, bo, cy }) do ok(c.ns.League.IsRival(c:G(), "Froga"), c.name .. ": Froga are rivals") end
	ok(Printed(sean, "Night Owls accepted your challenge!"), "card for the challenger's guild")
	ok(Printed(maria, "Night Owls accepted your challenge!"), "for every member")
	-- the Rivals view: this week's score (Froga wins gold, damage, quests, kills; crafts tied)
	sean.ns.db.ui.leagueView = "rivals"
	sean:Slash("league")
	local list, title = sean.ns.UI.LeagueTexts()
	eq(#list, 1, "one rival")
	contains(Plain(list[1]), "Night Owls | 4.5 - 3.5  lead | 0W 0L 0D", "score, lead and record")
	contains(Plain(title), "Froga   4.5 - 3.5   Night Owls", "match header")
	local sc = ana.ns.League.Score(ana.ns.League.Sheet(ana:G()), ana.ns.League.TheirSheet("Froga"))
	eq(sc.us, 3.5, "Night Owls see 3.5"); eq(sc.them, 4.5, "and Froga 4.5")
	eq(#w:Errors(), 0, "no errors")
end)

test("guild vs guild: lead changes make a card; the week's result is recorded once and announced once", function()
	local w = NewWorld()
	local kurt, sean, maria, ana, bo, cy = TwoGuilds(w)
	for _, c in ipairs({ kurt, sean, maria, ana, bo, cy }) do c:Login() end
	for _, c in ipairs({ kurt, ana }) do c:G().rules.announceMVP = true; c.ns.Comm.PublishRules() end
	SeedAll({ kurt, sean, maria }, { ana, bo, cy })
	w:Advance(700)
	sean.ns.League.Challenge("Night Owls")
	w:Advance(10)
	ana.ns.League.Answer(next(ana.ns.League.PendingInvites()), true)
	w:Advance(700)
	eq(sean:G().rivals["Night Owls"].leadState, "lead", "Froga leads")
	-- Night Owls pull ahead
	local big = { playtime = 3600, g_loot = 90000, mlevels = 1500, damage = 150000, healing = 30000, quests = 9, kills = 30, gathers = 4, crafts = 2 }
	for _, c in ipairs({ ana, bo, cy }) do Seed(c, { "Ana", "Bo", "Cy" }, big) end
	w:Advance(700)
	eq(sean:G().rivals["Night Owls"].leadState, "behind", "now behind")
	ok(Printed(sean, "Night Owls took the lead against Froga"), "lead change card")
	-- the league week ends: result recorded, guild chat line once per guild
	-- (put Froga back on top first so the result is a win)
	for _, c in ipairs({ ana, bo, cy }) do Seed(c, { "Ana", "Bo", "Cy" }, OWLS) end
	w:Advance(700)
	Jump(w, 7 * 86400)
	w:Advance(120)
	local r = sean:G().rivals["Night Owls"]
	eq(r.record.w, 1, "a win on the record")
	eq(r.lastResult.result, "w", "last result")
	eq(maria:G().rivals["Night Owls"].record.w, 1, "every member records it")
	eq(ana:G().rivals["Froga"].record.l, 1, "Night Owls record a loss")
	local posts, theirs = 0, 0
	for _, line in ipairs(w.chat) do
		if line.msg:find("Froga beat Night Owls 4.5-3.5 last week!", 1, true) then posts = posts + 1 end
		if line.msg:find("Night Owls lost to Froga 3.5-4.5 last week.", 1, true) then theirs = theirs + 1 end
	end
	eq(posts, 1, "Froga announces once")
	eq(theirs, 1, "Night Owls announce once")
	-- shown in the weekly popup, the rivals view and Discord text
	maria.ns.db.ui.welcomed = true
	ok(maria.ns.Alerts.ShowWeeklyPopup(maria:G()), "weekly popup")
	contains(Plain(maria.ns.Alerts.WeeklyPopupText()), "Guild vs Guild: beat Night Owls 4.5-3.5", "result in the popup")
	maria.ns.db.ui.leagueView = "rivals"
	maria:Slash("league")
	local list, _, history = maria.ns.UI.LeagueTexts()
	contains(Plain(list[1]), "1W 0L 0D", "record in the list")
	contains(Plain(history), "won 4.5-3.5", "past weeks line")
	local discord = table.concat(maria.ns.BuildDiscordText(maria:G(), "lastweek"), "\n")
	contains(discord, ":crossed_swords: **Guild vs Guild:** beat Night Owls 4.5-3.5", "result in Discord text")
	-- doesn't count twice
	w:Advance(600)
	eq(sean:G().rivals["Night Owls"].record.w, 1, "still one win")
	eq(#w:Errors(), 0, "no errors")
end)

test("guild vs guild: without the league channel, officers challenge by name over whispers", function()
	local w = NewWorld()
	w.noChannels = true
	local kurt, sean, maria, ana, bo, cy = TwoGuilds(w)
	for _, c in ipairs({ kurt, sean, maria, ana, bo, cy }) do c:Login() end
	SeedAll({ kurt, sean, maria }, { ana, bo, cy })
	w:Advance(700)
	eq(sean.ns.League.TheirSheet("Night Owls"), nil, "nobody heard without the channel")
	sean.ns.db.ui.welcomed, sean.ns.db.ui.leagueView = true, "all"
	sean:Slash("league")
	-- Sean types Bo (a member): Bo's officers get the request, Bo tells Sean who they are
	ok(sean.ns.LeagueUI.ShowNameDialog(), "dialog")
	ok(sean.ns.LeagueUI.SendByName("Bo"), "sent by name")
	w:Advance(10)
	ok(Printed(sean, "Bo can't accept for Night Owls. Try one of their officers: Ana"), "Bo points at Ana")
	contains(Plain(ana.ns.LeagueUI.InviteText() or ""), "<Froga> challenges your guild", "Ana gets the invite through her guild")
	ana.ns.LeagueUI.ClickInvite(true)
	w:Advance(15)
	ok(sean.ns.League.IsRival(sean:G(), "Night Owls"), "Sean: rivals")
	ok(kurt.ns.League.IsRival(kurt:G(), "Night Owls"), "Kurt: rivals")
	ok(cy.ns.League.IsRival(cy:G(), "Froga"), "Cy: rivals")
	ok(sean.ns.League.TheirSheet("Night Owls"), "sheets swapped by whisper")
	ok(ana.ns.League.TheirSheet("Froga"), "both ways")
	w:Advance(30)
	ok(kurt.ns.League.TheirSheet("Night Owls"), "passed on inside Froga")
	ok(bo.ns.League.TheirSheet("Froga"), "passed on inside Night Owls")
	-- later, stale sheets are asked for by whisper
	local before = #w:MessagesOfKind("G")
	local atBefore = sean.ns.League.TheirSheet("Night Owls").at
	w:Advance(2400)
	local queries = 0
	for _, s in ipairs(w.sent) do if s.chatType == "WHISPER" and s.msg:find(";q;", 1, true) then queries = queries + 1 end end
	ok(queries >= 1, "stale rival asked by whisper")
	ok(sean.ns.League.TheirSheet("Night Owls").at > atBefore, "sheet refreshed by the answer")
	ok(#w:MessagesOfKind("G") > before, "messages flowed")
	-- footer says the channel is unavailable
	eq(sean.ns.League.Status().channel, false, "no channel")
	eq(#w:Errors(), 0, "no errors")
end)

test("guild vs guild: a hidden guild isn't listed, can't challenge and ignores challenges", function()
	local w = NewWorld()
	local kurt, sean, maria, ana, bo, cy = TwoGuilds(w)
	for _, c in ipairs({ kurt, sean, maria, ana, bo, cy }) do c:Login() end
	-- Ana hides Night Owls (officer setting, shared with the guild)
	ana:G().rules.leagueHidden = true
	ana.ns.Comm.PublishRules()
	w:Advance(20)
	eq(bo:G().rules.leagueHidden, true, "the setting reaches members")
	SeedAll({ kurt, sean, maria }, { ana, bo, cy })
	w:Advance(700)
	eq(sean.ns.League.TheirSheet("Night Owls"), nil, "hidden guild sends no sheet")
	ok(bo.ns.League.TheirSheet("Froga"), "but still sees others")
	local dir = bo.ns.League.Directory(bo:G())
	for _, item in ipairs(dir) do ok(item.name ~= "Night Owls", "own hidden guild not listed") end
	local okay, err = ana.ns.League.Challenge("Froga")
	eq(okay, false, "hidden guild can't challenge"); contains(err or "", "hidden", "says why")
	sean.ns.League.Challenge(nil, "Ana")
	w:Advance(10)
	eq(ana.ns.LeagueUI.InviteText(), nil, "challenge ignored")
	ok(not sean.ns.League.IsRival(sean:G(), "Night Owls"), "no rivalry")
	-- settings checkbox and summary line
	contains(Plain(ana.ns.UI.RulesSummary(ana:G())), "Guild vs Guild:  hidden", "rules summary")
	eq(#w:Errors(), 0, "no errors")
end)

test("guild vs guild: rivals reach guildmates who were offline; ending a rivalry reaches both guilds", function()
	local w = NewWorld()
	local kurt, sean, maria, ana, bo, cy = TwoGuilds(w)
	for _, c in ipairs({ kurt, sean, ana, bo }) do c:Login() end
	SeedAll({ kurt, sean }, { ana, bo })
	w:Advance(700)
	sean.ns.League.Challenge("Night Owls")
	w:Advance(10)
	ana.ns.League.Answer(next(ana.ns.League.PendingInvites()), true)
	w:Advance(15)
	maria:Login(); cy:Login()
	w:Advance(120)
	maria.ns.Comm.SyncNow(); cy.ns.Comm.SyncNow()
	w:Advance(120)
	ok(maria.ns.League.IsRival(maria:G(), "Night Owls"), "Maria learns the rivalry")
	ok(cy.ns.League.IsRival(cy:G(), "Froga"), "Cy learns it too")
	-- Kurt (guild master) ends it
	ok(kurt.ns.League.EndRivalry("Night Owls"), "ended")
	w:Advance(15)
	ok(not sean.ns.League.IsRival(sean:G(), "Night Owls"), "Sean")
	ok(not maria.ns.League.IsRival(maria:G(), "Night Owls"), "Maria")
	ok(not ana.ns.League.IsRival(ana:G(), "Froga"), "Ana")
	ok(Printed(ana, "Froga ended the guild vs guild rivalry."), "Night Owls told")
	eq(maria.ns.League.EndRivalry("Night Owls"), false, "members can't end one")
	-- a fresh challenge works again afterwards
	sean.ns.League.Challenge("Night Owls")
	w:Advance(10)
	ana.ns.League.Answer(next(ana.ns.League.PendingInvites()), true)
	w:Advance(15)
	ok(maria.ns.League.IsRival(maria:G(), "Night Owls"), "rivals again")
	eq(#w:Errors(), 0, "no errors")
end)

test("guild vs guild: unbelievable or broken sheets are ignored; at most 5 rivals", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	w:Advance(20)
	local LG, g = sean.ns.League, sean:G()
	local week = LG.Week()
	local function Feed(guild, vals, q)
		local msg = string.format("G;%d;b;%s;%s;%d;10;%s", sean.ns.PROTO, guild, week, q or 5, vals)
		local parts = {}
		for p in (msg .. ";"):gmatch("(.-);") do parts[#parts + 1] = p end
		LG.Handle(g, "Stranger", parts, "CHANNEL", "GuildRanksLeague")
	end
	Feed("Cheaters", "zzzzzzzz,1,1,1,1,1,1,1") -- billions of copper per hour
	eq(LG.TheirSheet("Cheaters"), nil, "absurd gold ignored")
	Feed("Broken", "1,2,3")
	eq(LG.TheirSheet("Broken"), nil, "wrong number of values ignored")
	Feed("Fine", "1000,a,1,1,1,1,1,1")
	ok(LG.TheirSheet("Fine"), "a normal sheet is kept")
	-- messages from other channels are ignored
	local parts = { "G", tostring(sean.ns.PROTO), "b", "Elsewhere", week, "5", "10", "1,1,1,1,1,1,1,1" }
	LG.Handle(g, "Stranger", parts, "CHANNEL", "Trade - City")
	eq(LG.TheirSheet("Elsewhere"), nil, "other channels ignored")
	-- five rivals at most
	for i = 1, 5 do g.rivals["Rival" .. i] = { since = 1000, record = { w = 0, l = 0, d = 0 }, history = {} } end
	local okay, err = LG.Challenge("Fine")
	eq(okay, false, "sixth refused"); contains(err or "", "5 rival guilds", "says why")
	eq(#w:Errors(), 0, "no errors")
end)

test("guild vs guild: the tab works with no rivals, solo, in demo mode and without the channel", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	local solo = w:NewClient({ name = "Lone" })
	for _, c in ipairs({ kurt, sean, maria, solo }) do c:Login(); c.ns.db.ui.welcomed = true end
	w:Advance(60)
	sean:Slash("league")
	local list = sean.ns.UI.LeagueTexts()
	eq(#list, 0, "no rivals yet")
	sean.ns.db.ui.leagueView = "all"
	sean:Slash("league")
	eq(#sean.ns.UI.DirectoryTexts(), 1, "just Froga")
	solo:Slash("league")
	sean:Slash("demo"); sean:Slash("league"); sean:Slash("demo off")
	eq(#w:Errors(), 0, "no errors")
end)
