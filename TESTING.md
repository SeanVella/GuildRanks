# Testing Guild Ranks

Guild Ranks is tested in three layers: an automated simulated guild that runs on
every change, in-game test tools for players, and a beta channel for real guilds.

## 1. Automated tests (simulated guild)

`tests/wow.lua` is a small simulated World of Warcraft. Several players each run
their own copy of the addon and talk over a shared guild addon channel with
Blizzard's real limits:

- per-prefix throttle (10 messages burst, then 1 per second) and the 255-character limit
- combat "secret values" (hidden money, XP and damage meter that can't be used in maths)
- instances and chat lockdown (addon messages blocked)
- a game clock with timers, realm calendar, midnight and weekly reset
- guild roster (online/offline, ranks, incomplete rosters), same-name guilds
- optional addons: TradeSkillMaster, Auctionator, LibDataBroker/LibDBIcon

112 scenario tests cover tracking (every gold source, XP across level-ups, kills,
crafts, loot value, gathering, bosses and runs, damage meter, AFK time), guild
sync (sharing, relays for offline members, throttle, privacy), guild rules and
permissions, guild detection, dates, scoring, the Discord text, the Hall of Fame,
session bar, alerts, weekly popup, reset hour, play time privacy, sync timing, tabs, ranking chips, rank changes, player cards, online status, personal bests, goals, weekly titles, rival, session recap, race to 60, member activity, professions, 1v1 challenges, guild vs guild (league channel, challenge by name over whispers, hidden guilds, rival sync, weekly results, fake sheets), WoW: Forever names (shifting realms, longer names, merging old duplicates), lead cards, weekly popup sharing, officer invite nudge, first-open welcome, own-spell healing, damage spike protection, deaths, invite, settings for members and officers, welcome, announcements, version notice, integrations,
the in-game tools and every window page. Any Lua error inside the addon fails the
test.

Run them from the repository root:

```bash
lua5.1 tests/run_all.lua            # everything (also works with lua5.3 / texlua)
lua5.1 tests/run_all.lua sync       # only files whose name contains "sync"
```

GitHub Actions runs all of this on every push and pull request, on Lua 5.1 (the
version WoW uses) and Lua 5.3, and again before every release.

Writing a test:

```lua
test("Kurt sees Sean's gold", function()
	local w = NewWorld()
	local kurt, sean = StandardGuild(w)   -- Kurt (GM), Sean (officer), Maria (member)
	kurt:Login(); sean:Login()
	sean:Fire("LOOT_OPENED"); sean:GainMoney(1500); sean:Fire("LOOT_CLOSED")
	w:Advance(90)                         -- 90 simulated seconds
	eq(kurt:G().players[sean.key].days[kurt.ns.Today()].g_loot, 1500, "gold")
end)
```

## 2. In-game test tools

| Command | What it does |
|---|---|
| `/granks selftest` | Checks every game feature the addon relies on (guild, roster, calendar, addon messages, damage meter, game texts, gathering spells, events) and prints PASS / WARN / FAIL |
| `/granks demo` | Fills the window with clearly labelled sample guild data, to preview everything alone or take screenshots. `/granks demo off` removes it. Demo data is never shared or exported |
| `/granks log` | The last tracked changes and where they were counted (e.g. "+5g quest"), to confirm tracking |
| `/granks diag` | Technical details for bug reports |

## 3. Beta with a real guild

1. Tag a beta: `git tag v1.1.0-beta.1 && git push origin v1.1.0-beta.1`. The
   release workflow runs the tests, then publishes it as a **beta** file on
   CurseForge/Wago (testers set their addon manager to accept beta versions).
2. Testers report problems with the GitHub **Bug report** form, which asks for
   `/granks diag` and `/granks selftest`.
3. Guildmates on older versions are told in game that a newer version is in use.

### Beta checklist (two or three guild members online)

- [ ] `/granks selftest` shows no FAIL for everyone
- [ ] Each player sees the others within a minute (`/granks sync` if not)
- [ ] Loot gold, hand in a quest, sell to a vendor, take mail: `/granks log` shows the right source
- [ ] Collect Auction House sales from the mailbox: Gold and Gold/h don't change (unless the guild turned AH on)
- [ ] After a fight, damage appears (selftest "Damage meter readable" should PASS out of combat)
- [ ] An officer changes a rule and saves: every member sees it in Settings
- [ ] Log out one member; a new member logging in still sees the logged-out member's stats
- [ ] Turn off "Share my stats": you disappear from guildmates' boards
- [ ] Copy for Discord pastes cleanly into a Discord channel
- [ ] Session bar, Hall of Fame and weekly challenge/goal banner look right (`/granks demo` helps)
- [ ] After the weekly reset: weekly popup appears once; MVP posted once in guild chat (if enabled)
- [ ] `/reload`: everything is still there
- [ ] Race to 60 chip: players at 60 listed first-to-last with date and play time; others with an estimate
- [ ] Members > Activity: last seen and hours this week; as an officer, inactive members in red with a count
- [ ] Members > Professions: your professions and guildmates' appear; a skill-up shows within a minute
- [ ] Two players: Challenge from the player card, Accept, both see the race bar; the winner can post the result
- [ ] Each guildmate appears once on the leaderboard, under their full name; you appear as your full name (e.g. "Healya Jamie")
- [ ] Drink a healing potion or use a healthstone: your Healing doesn't go up; a heal spell does
- [ ] Die once (not Feign Death): Deaths goes up by exactly 1; Copy for Discord shows "Fewest deaths"
- [ ] Zone into a dungeon and out again: Damage doesn't jump (compare `/granks log` before and after)
- [ ] Take #1 in a ranking: a gold lead card with a sound; the player you passed gets a grey card
- [ ] Log out and back in: the session recap shows Gold/Experience/Levels, the six activity tiles and any personal bests, with the buttons below the tiles
- [ ] After the weekly reset: the popup shows the podium; "Post to guild chat" posts your result once
- [ ] As an officer with some members missing the addon: the Members tab shows the invite nudge; "Not now" hides it
- [ ] A new member's first open shows "You're #N in <guild>!" with guildmates' names
- [ ] Guild vs Guild (two guilds): within ~10 min each guild appears under All guilds (footer says "League channel connected")
- [ ] An officer presses Challenge; an officer of the other guild gets the popup and accepts; both see each other under Rivals with a score
- [ ] If All guilds stays empty: Challenge by name with a member of the other guild works; a non-officer replies with their officers' names
- [ ] Settings > Guild rules > "Hide our guild from the public league": the guild disappears from the other guild's list
- [ ] After the Wednesday reset: the result is in the weekly popup and Copy for Discord, and posted once in guild chat (if MVP posting is on)
