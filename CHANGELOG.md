# Changelog

## 1.1.0

New
- Me tab: your stats (today, this week, all time) with the change since the previous period,
  a 7-day chart, personal goals with pace, personal bests ("New personal best!" toast), a rival
  (head to head plus alerts when either of you passes the other) and weekly titles for last
  week's #1 in each ranking, one of which you can show to your guild (checked by everyone's
  addon, so titles can't be faked).
- Session recap at your next login (not after a /reload) and with `/granks recap`.
- Redesigned window: tabs (Ranks, Hall of Fame, Members, Settings), a cleaner title (the guild
  picker only appears if your characters are in several guilds) and a compact award strip that
  only shows last week's awards, the challenge and the goal when there's something to show.
- One-click ranking chips (Score, Gold, XP, Damage, Quests, plus More rankings), score bars,
  and each player's rank change since the previous period (+2, -1, new).
- Online status: a green dot next to guildmates who are online, an "Online only" filter
  (rank numbers stay the same) and the online count in the footer.
- Player cards: click a name for the score breakdown, all stats, gold by source and recent weeks.
- Invite button: post an install message in guild chat or copy it for Discord (`/granks invite`).
- Settings split into "You" and "Guild rules"; members see a plain summary of the rules,
  officers get tooltips, "Unsaved changes", Save and Discard.
- First-time welcome with a sample-data preview (`/granks welcome`), and friendlier empty states.
- Weekly reset hour: leaders choose the hour (realm time) as well as the day; the window
  shows "Resets Wed 18 Nov, 05:00 realm time · in 2d 9h".
- Play time privacy: "Show my play time to my guild" (personal) and "Show play time"
  (guild rule). Hidden play time shows as "hidden" and is left out of the Play time ranking.
- `/granks diag` shows guild sync timing: messages waiting and time to send them, the
  last send and full sync (how long, how many messages and members), latest data per guildmate.
- Own Guild Ranks icon, and a minimap button for everyone (LibDBIcon is now bundled;
  drag it around the minimap, hide it with `/granks minimap`).
- Session bar: rank this week, gold/XP per hour this session, time to level (`/granks bar`).
- Rank-change alerts ("Kurt just passed you in Gold/h") and a weekly results popup after the reset.
- Hall of Fame: MVP counts, best week per ranking, top-3 streaks, weekly results history;
  MVP trophies next to names; recent weeks in each player's tooltip.
- Weekly challenge (featured ranking + prize) and guild goal (combined weekly total), set by officers.
- Optional guild chat announcements: your level-ups, and last week's MVP (posted once per guild).
- Notice when a newer version is used in your guild.
- In-game test tools: `/granks selftest`, `/granks demo`, `/granks log`.

Removed
- The optional automatic Discord posting through GitHub (bot, workflows, uploader) and the
  export it read (`/granks export`). Old export data is deleted from save files.
  Use **Copy for Discord** to share results.

Fixes
- Discord text no longer lists empty rankings (e.g. "Deaths 0.0/h" when nobody died).
- Rule updates that arrive before the guild roster has loaded are applied once it loads.
- The realm day uses server time until the game calendar is ready (never the PC clock).
- An incomplete roster from the server no longer hides members from the leaderboard.
- Offline members' data is relayed to every new login (relay cooldown was too long),
  and the roster is refreshed before relaying.
- Opening a page before the main window had been shown no longer errors.
- `/granks demo` (and "Show sample data") no longer closes the window when it's already open.
- Two members logging in within a minute of each other both get the guild's data
  (the second request used to be ignored; it is now answered when the minute is up).

Testing
- Automated simulated-guild test suite (79 tests) on Lua 5.1 and 5.3 in GitHub Actions;
  tests run before every release.
- Bug report and feature request forms; beta releases via `-beta` tags.

## 1.0.0 — first public release

- Guild leaderboards for 14 rankings, per hour or totals, by period and level range.
- Guild score (0-100) from 8 equally weighted categories; weekly MVP and optional Wooden spoon.
- Automatic guild detection with per-guild data and a guild switcher; solo mode outside a guild.
- Members page: roster, who uses the addon, versions; officers can exclude players.
- Guild rules shared by the Guild Master and chosen ranks: reset day, minimum play time,
  gold sources, loot value source, Wooden spoon on/off.
- "Share my stats" privacy switch.
- Copy for Discord.
- Integrations: TradeSkillMaster / Auctionator prices, LibDataBroker data text, LibDBIcon minimap button.
- Language-independent detection of kills, crafting, loot and gathering.
- Compact, rate-limited guild sync for large guilds.
- Optional GitHub automation for weekly Discord posts (docs/discord-automation.md).
