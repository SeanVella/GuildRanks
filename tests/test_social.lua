-- Race to max level, Members > Activity and Professions, 1v1 challenges

local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")) end

local function Loot(c, copper) c:Fire("LOOT_OPENED"); c:GainMoney(copper); c:Fire("LOOT_CLOSED") end

local function ChatHas(w, text)
	for _, line in ipairs(w.chat) do if line.msg:find(text, 1, true) then return line.msg end end
	return nil
end

test("race to 60: reaching max level is recorded with /played, celebrated, shared and ranked", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt.level, maria.level = 59, 60
	kurt:Login(); sean:Login(); maria:Login()
	w:Advance(60)
	-- Maria was already 60 when Guild Ranks first saw her: date unknown
	ok(maria.ns.db.chars[maria.key].maxUnknown, "Maria: reached before tracking")
	kurt.played = 4 * 86400 + 9 * 3600
	kurt.level = 60
	kurt:Fire("PLAYER_LEVEL_UP", 60)
	w:Advance(3)
	local c = kurt.ns.db.chars[kurt.key]
	ok(c.maxAt, "date recorded")
	eq(c.maxPlayed, 4 * 86400 + 9 * 3600, "/played recorded")
	contains(kurt.ns.Alerts.CardText() or "", "You reached level 60!", "card for Kurt")
	local msg = ChatHas(w, "Kurt reached 60!")
	ok(msg, "announced in guild chat")
	contains(msg, "2nd in Froga", "Maria got there first (before tracking)")
	contains(msg, "4d 9h", "play time in the shout-out")
	w:Advance(120); kurt.ns.Comm.SyncNow(); w:Advance(60)
	local reached, levelling = sean.ns.Race.Board(sean:G())
	eq(#reached, 2, "two at 60 on Sean's board")
	eq(reached[1].name, "Kurt", "known date first")
	eq(reached[1].played, 4 * 86400 + 9 * 3600, "Kurt's play time arrived")
	eq(reached[2].name, "Maria", "unknown date after")
	eq(levelling[1].name, "Sean", "Sean still levelling")
	-- the Race chip shows it
	sean.ns.db.ui.welcomed = true
	sean:Slash("race")
	local rows = sean.ns.UI.VisibleRows()
	eq(rows[1].name:find("Kurt", 1, true) ~= nil, true, "Kurt first on the Race board")
	-- once only, and not when switched off
	kurt:Fire("PLAYER_LEVEL_UP", 60); w:Advance(3)
	local count = 0
	for _, line in ipairs(w.chat) do if line.msg:find("Kurt reached 60!", 1, true) then count = count + 1 end end
	eq(count, 1, "celebrated once")
end)

test("race to 60: levelling estimate from this week's pace; no announcement when switched off", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	sean.level = 50
	kurt:Login(); sean:Login()
	w:Advance(30)
	local g = sean:G()
	local p = sean.ns.GetPlayer(g, sean.key)
	p.days[sean.ns.Today()] = { playtime = 7200, mlevels = 2000 } -- 1 level per hour
	p.level = 50
	local _, levelling = sean.ns.Race.Board(g)
	local me
	for _, e in ipairs(levelling) do if e.key == sean.key then me = e end end
	ok(me and me.etaSecs, "estimate")
	near(me.etaSecs, 10 * 3600, 1, "10 levels at 1 level/hour")
	sean.ns.db.announceMax = false
	sean.played = 1000
	sean.level = 60
	sean:Fire("PLAYER_LEVEL_UP", 60); w:Advance(3)
	eq(ChatHas(w, "reached 60"), nil, "no guild chat when switched off")
	ok(sean.ns.db.chars[sean.key].maxAt, "still recorded")
end)

test("members > activity: online first, last seen, play time; inactive flag for officers only", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	w:AddRosterMember("Froga", "Oldie-Firemaw", 4, 34, "ROGUE")
	w.guilds.Froga.members["Oldie-Firemaw"].lastDays = 19
	w:AddRosterMember("Froga", "Recent-Firemaw", 4, 20, "MAGE")
	w.guilds.Froga.members["Recent-Firemaw"].lastDays = 2.5
	kurt:Login(); sean:Login()
	w:Advance(30)
	sean.ns.db.ui.welcomed = true
	sean.ns.GetPlayer(sean:G(), sean.key).days[sean.ns.Today()] = { playtime = 7200 }
	sean.ns.ReadRoster()
	sean.ns.db.ui.membersView = "activity"
	sean.ns.UI.Show("members")
	local rows = sean.ns.UI.ActivityTexts()
	ok(#rows >= 5, "everyone in the roster")
	contains(Plain(rows[1]), "online", "online members first")
	local text = Plain(table.concat(rows, "\n"))
	contains(text, "Oldie | 19 days ago", "last seen")
	contains(text, "Recent | 2 days ago", "recent")
	contains(text, "Sean | online | 2h 00m", "play time this week")
	local _, sw, _, footer = sean.ns.UI.Internals()
	contains(footer:GetText(), "1 member inactive 14+ days", "officer sees the inactive count")
	contains(rows[#rows], "|cffff5050", "inactive member shown in red for officers")
	-- a plain member: no flag
	maria:Login(); w:Advance(30)
	maria.ns.db.ui.welcomed = true
	maria.ns.ReadRoster()
	maria.ns.db.ui.membersView = "activity"
	maria.ns.UI.Show("members")
	local mrows = maria.ns.UI.ActivityTexts()
	for _, r in ipairs(mrows) do absent(r, "|cffff5050", "members don't see the flag") end
	local _, _, _, mfooter = maria.ns.UI.Internals()
	absent(mfooter:GetText(), "inactive", "no inactive count for members")
	-- officers can change the number of days in the rules (shared with the guild)
	sean:G().rules.inactiveDays = 30
	sean.ns.Comm.PublishRules(); w:Advance(30)
	eq(maria:G().rules.inactiveDays, 30, "rule shared")
	sean.ns.UI.Refresh()
	contains(footer:GetText(), "Nobody inactive for 30+ days", "nobody past 30 days")
end)

test("members > professions: shared at login and when skills change; listed highest first", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt.profs = { { "Blacksmithing", 300, 300, 164 }, { "Mining", 250, 300, 186 } }
	sean.profs = { { "Mining", 120, 150, 186 }, { "Alchemy", 80, 150, 171 } }
	kurt:Login(); sean:Login()
	w:Advance(120); kurt.ns.Comm.SyncNow(); sean.ns.Comm.SyncNow(); w:Advance(60)
	local dir = sean.ns.Social.Directory(sean:G())
	local byName = {}
	for _, pr in ipairs(dir) do byName[pr.name] = pr.members end
	ok(byName.Blacksmithing and byName.Blacksmithing[1].name == "Kurt", "Kurt's blacksmithing arrived")
	eq(byName.Mining[1].name, "Kurt", "highest skill first")
	eq(byName.Mining[2].name, "Sean", "then Sean")
	sean.ns.db.ui.welcomed = true
	sean.ns.db.ui.membersView = "professions"
	sean.ns.UI.Show("members")
	local text = Plain(sean.ns.UI.ProfessionsText())
	contains(text, "Alchemy   Sean 80", "own professions listed")
	contains(text, "Blacksmithing   Kurt 300", "guildmate listed")
	contains(sean.ns.UI.ProfessionsText(), "|Hplayer:Kurt|h", "click a name to whisper")
	-- a skill-up is shared
	kurt.profs[2][2] = 260
	kurt:Fire("SKILL_LINES_CHANGED"); w:Advance(30)
	dir = sean.ns.Social.Directory(sean:G())
	for _, pr in ipairs(dir) do if pr.name == "Mining" then eq(pr.members[1].skill, 260, "skill-up shared") end end
end)

test("1v1: challenge, accept, race, result; winner can post, loser can't", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)
	kurt:Login(); sean:Login()
	w:Advance(120); kurt.ns.Comm.SyncNow(); sean.ns.Comm.SyncNow(); w:Advance(60)
	sean.ns.ReadRoster()
	ok(sean.ns.Versus.CanChallenge(kurt.key), "Kurt can be challenged")
	ok(not sean.ns.Versus.CanChallenge(sean.key), "not yourself")
	sean:Slash("challenge")
	local target, metric, secs = sean.ns.VersusUI.DialogState()
	eq(target, kurt.key, "Kurt picked")
	eq(metric, "gold", "gold by default")
	eq(secs, 3600, "1 hour by default")
	sean.ns.VersusUI.SendFromDialog()
	w:Advance(5)
	contains(Plain(kurt.ns.VersusUI.InviteText()), "Sean challenges you to a 1-hour gold race!", "Kurt gets the popup")
	kurt.ns.Versus.Answer(true)
	w:Advance(5)
	ok(sean.ns.Versus.Current() and sean.ns.Versus.Current().started, "race started for Sean")
	ok(kurt.ns.Versus.Current() and kurt.ns.Versus.Current().started, "and for Kurt")
	Loot(sean, 50000); Loot(kurt, 20000)
	w:Advance(60)
	contains(Plain(sean.ns.VersusUI.BarText()), "+5g 0s | +2g 0s", "live progress on both sides")
	w:Advance(3600)
	local r = sean.ns.Versus.Current()
	ok(r.done and r.won, "Sean won")
	ok(kurt.ns.Versus.Current().done and not kurt.ns.Versus.Current().won, "Kurt lost")
	contains(Plain(sean.ns.VersusUI.BarText()), "You won!", "result on the bar")
	eq(kurt.ns.Versus.PostResult(), false, "loser can't post")
	sean.ns.VersusUI.ClickLeft() -- Post to guild chat
	local msg = ChatHas(w, "I won a 1-hour gold race against Kurt")
	ok(msg, "winner posted the result")
	contains(msg, "5g 0s vs 2g 0s", "with both totals")
end)

test("1v1: decline, give up, and only one race at a time", function()
	local w = NewWorld()
	local kurt, sean, maria = StandardGuild(w)
	kurt:Login(); sean:Login(); maria:Login()
	w:Advance(120); kurt.ns.Comm.SyncNow(); sean.ns.Comm.SyncNow(); maria.ns.Comm.SyncNow(); w:Advance(60)
	sean.ns.ReadRoster()
	ok(sean.ns.Versus.Challenge(kurt.key, "kills", 1800), "challenge sent")
	w:Advance(5)
	kurt.ns.Versus.Answer(false)
	w:Advance(5)
	eq(sean.ns.Versus.Current(), nil, "declined: no race")
	local declined = false
	for _, line in ipairs(sean.printed) do if line:find("Kurt declined your challenge", 1, true) then declined = true end end
	ok(declined, "Sean is told")
	-- give up
	sean.ns.Versus.Challenge(kurt.key, "xp", 1800); w:Advance(5)
	kurt.ns.Versus.Answer(true); w:Advance(5)
	ok(not sean.ns.Versus.CanChallenge(maria.key), "busy: one race at a time")
	kurt.ns.Versus.GiveUp(); w:Advance(5)
	ok(sean.ns.Versus.Current().done and sean.ns.Versus.Current().won, "Sean wins when Kurt gives up")
	ok(sean.ns.Versus.PostResult(), "and may post it")
	ok(ChatHas(w, "(they gave up)"), "says they gave up")
end)
