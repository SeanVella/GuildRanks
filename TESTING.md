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

70 scenario tests cover tracking (every gold source, XP across level-ups, kills,
crafts, loot value, gathering, bosses and runs, damage meter, AFK time), guild
sync (sharing, relays for offline members, throttle, privacy), guild rules and
permissions, guild detection, dates, scoring, the Discord text, the Hall of Fame,
session bar, alerts, weekly popup, reset hour, play time privacy, sync timing, tabs, ranking chips, rank changes, player cards, invite, settings for members and officers, welcome, announcements, version notice, integrations,
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
- [ ] After a fight, damage appears (selftest "Damage meter readable" should PASS out of combat)
- [ ] An officer changes a rule and saves: every member sees it in Settings
- [ ] Log out one member; a new member logging in still sees the logged-out member's stats
- [ ] Turn off "Share my stats": you disappear from guildmates' boards
- [ ] Copy for Discord pastes cleanly into a Discord channel
- [ ] Session bar, Hall of Fame and weekly challenge/goal banner look right (`/granks demo` helps)
- [ ] After the weekly reset: weekly popup appears once; MVP posted once in guild chat (if enabled)
- [ ] `/reload`: everything is still there
