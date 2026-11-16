# Guild Ranks

**Friendly competition for your whole guild in World of Warcraft: Forever.**
Guild Ranks ranks your guildmates by gold, XP, damage, healing, quests, kills,
gathering, crafting and more, **per hour of play**, combines it into one fair
**Guild score**, and every week names an **MVP** (and, if your guild wants it, a
**Wooden spoon**). Share the results in Discord with one click.

Works for any guild, automatically. Install it, and it detects your guild by
itself.

## Features

- **Leaderboards for 14 rankings** — Guild score, gold earned, loot value, XP,
  levels gained, damage, healing, kills, quests, bosses, dungeon/raid runs,
  gathering, crafting, fewest deaths and play time. Per hour or totals; today,
  this week, last week, this month or all time; filter by level range. The most
  used rankings are one click away, with score bars and each player's rank change
  since last week (+2, -1, new).
- **Player cards** — click a name for their Guild score broken down by category,
  every stat (total and per hour), gold by source and their recent weeks.
- **Guild score (0-100)** — placement across 8 equally weighted categories (gold,
  levels gained, combat, quests, kills, bosses and runs, gathering and crafting,
  fewest deaths). Fair by design: per hour of play, healers ranked on healing,
  "levels gained" instead of raw XP, and a minimum play time to qualify.
- **Weekly MVP and Wooden spoon** — shown in game, in the minimap/data-text tooltip
  and in the Discord post. Guilds can turn the Wooden spoon off.
- **Copy for Discord** — results as ready-to-paste Discord text. No setup.
- **Automatic guild detection** — your data is kept per guild; switch between the
  guilds your alts are in. Not in a guild? You still get your own stats.
- **Members page** — who in the roster uses the addon (and which version), so you
  can invite the rest with the **Invite** button (posts an install message in guild
  chat, or copy it for Discord). Officers can exclude cheaters from the rankings.
- **Guild rules, set by your leaders** — weekly reset day and hour (realm time;
  the window shows when the week resets and a countdown), minimum play time,
  which gold sources count (e.g. not mail from alts), vendor or auction prices
  for loot value. The Guild Master chooses which ranks may change them.
- **Privacy** — every member can switch off "Share my stats with my guild";
  their stats are then removed from guildmates' leaderboards. Members can also
  hide just their play time ("Show my play time to my guild"), and leaders can
  hide play time for everyone. Per-hour rankings still use it behind the scenes.
- **Integrations (optional)** — TradeSkillMaster or Auctionator auction prices
  for loot value (used only if installed); LibDataBroker data text for Titan Panel,
  ElvUI, Bazooka and others; a minimap button (LibDBIcon, bundled).
- **Session bar (optional)** — a small movable bar with your rank this week, this
  session's gold and XP per hour, and time to next level.
- **Hall of Fame** — MVP counts, best week per ranking, longest top-3 streaks and
  the weekly results history; MVP trophies next to names and each player's recent
  weeks in their tooltip.
- **Weekly challenge and guild goal** — officers feature one ranking (with an
  optional prize) and set a combined goal for the whole guild, shown in game and
  in Discord.
- **Alerts** — "Kurt just passed you in Gold/h", a "how you did" popup after the
  weekly reset, optional guild chat announcements (your level-ups, the weekly MVP),
  and a notice when a newer version is in use in your guild.
- **Any client language** — game messages and gathering spells are detected in
  your client's language. The interface is English for now and ready for
  translations (see *Contributing*).

## How it works

Each member's addon records **only their own character**, then shares it with the
guild over WoW's hidden guild addon channel; nothing leaves the guild and no
website is involved. That's why **everyone who wants to be ranked needs the
addon**. Members who are online also pass along recent data for members who are
offline, so leaderboards fill in quickly.

Sharing pauses inside dungeons and raids (Blizzard blocks addon messages there)
and resumes when you leave. Stats are self-reported, so treat it as a friendly
competition.

## Install

- **CurseForge / Wago app:** search for *Guild Ranks* and pick your **Forever**
  installation.
- **Manually:** download the latest zip from Releases and unzip it into
  `World of Warcraft\_forever_\Interface\AddOns\`, so that you get
  `AddOns\GuildRanks\GuildRanks.toc`.

## Use

| Command | What it does |
|---|---|
| `/granks` | Open the leaderboard (or click it in the addon menu / minimap button) |
| `/granks members` | Members page: who uses the addon, versions, exclusions |
| `/granks hall` | Hall of Fame |
| `/granks bar` | Show or hide the session bar |
| `/granks weekly` | Show last week's results popup again |
| `/granks settings` | Settings and guild rules |
| `/granks discord` | Copy the current view for Discord |
| `/granks invite` | Invite guildmates: post or copy an install message |
| `/granks welcome` | Show the welcome screen again |
| `/granks sync` | Ask the guild for fresh data |
| `/granks minimap` | Show or hide the minimap button |
| `/granks diag` | Diagnostics for bug reports, including guild sync timing (messages waiting, how long the last send and full sync took, latest data from each guildmate) |
| `/granks selftest` | Check that everything the addon needs works on your client |
| `/granks demo` / `demo off` | Preview the window with sample data |
| `/granks log` | The last tracked changes and where they were counted |

Click any name for that player's card: Guild score breakdown, every stat, where
their gold came from and their recent weeks.

## For guild leaders

Open **Settings → Guild rules** to set your guild's rules (reset day and hour, minimum play time, show play time, gold
sources, loot value, Wooden spoon, weekly challenge and prize, guild goal, MVP
announcement) and press **Save & share with guild**.
Everyone's addon then uses the same rules, so everyone sees the same rankings.
By default the Guild Master and the first officer rank can change rules; the Guild
Master can change that.

To share results in Discord, press **Copy for Discord** (or type `/granks discord`)
and paste into your channel. (WoW addons can't go online, so the addon can't post by itself.)

## What's measured, exactly

| Ranking | How |
|---|---|
| Gold earned | Money gained, split by source: loot, quests, vendor, Auction House, mail, trade, other. Spending isn't subtracted. |
| Loot value | Value of items you loot: vendor price, or TSM/Auctionator price if your guild chooses auction prices. |
| Experience / Levels gained | XP gained; "levels gained" is fair across levels (1.0 = one full level). |
| Damage / Healing | From Blizzard's built-in damage meter, read after each fight. |
| Kills | Kills that give XP (not inside instances or at max level). |
| Quests / Deaths | Quest turn-ins; your deaths (fewest wins). |
| Bosses / Runs | Boss kills; a dungeon or raid run counts once you kill a boss there. |
| Gathering / Crafts | Herbs, ore, skins, fishing catches; items you create. |
| Play time | Active time only (AFK time isn't counted). |

## Known limits

- Damage and healing depend on Blizzard's damage meter being readable after
  combat. If `/granks diag` shows the damage meter as hidden, those two rankings
  stay empty while everything else works. If damage stays at 0, turn on the
  built-in damage meter (*Options → Gameplay Enhancements*).
- Very large guilds: data sharing is rate-limited by Blizzard (about one message
  per second), so leaderboards can take a few minutes to fill after logging in.

## Roadmap

- Translations (German, French, Spanish, Italian, Portuguese...).
- Guild goals with several targets, seasonal (monthly) Hall of Fame.
- **Guild vs guild league** across realms: planned in
  [docs/guild-vs-guild-plan.md](docs/guild-vs-guild-plan.md).

## Testing

An automated simulated guild (70 scenario tests, run on Lua 5.1 and 5.3 on every
push) plus in-game test tools and a beta channel: see [TESTING.md](TESTING.md).

## Contributing

Bug reports and pull requests are welcome; use the GitHub issue forms, which ask
for `/granks diag` and `/granks selftest`. Please add or update a test in `tests/`
with code changes.

Translations: copy `Locales/enUS.lua` to `Locales/<locale>.lua`, follow the
instructions at the top, and add the file to `GuildRanks.toc`.

## Publishing (maintainers)

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager):
push a tag like `v1.1.0` (or `v1.1.0-beta.1` for a beta) and GitHub Actions runs the
tests, packages the addon and publishes it to
GitHub Releases, plus CurseForge and Wago once you:

1. Create the projects on CurseForge and Wago Addons (game version: WoW Forever).
2. Put their IDs in `GuildRanks.toc` (`## X-Curse-Project-ID:` and `## X-Wago-ID:`).
3. Add API tokens as repository secrets: `CF_API_KEY` (CurseForge → account →
   API tokens) and `WAGO_API_TOKEN` (Wago → account → API keys).

## License

MIT — see [LICENSE](LICENSE). Guild Ranks is free and always will be, in line with
Blizzard's UI Add-On Development Policy.
