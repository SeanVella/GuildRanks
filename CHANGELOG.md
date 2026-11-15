# Changelog

## 1.1.0

New
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
- Discord bot: weekly challenge winner and guild goal in the weekly post.

Fixes
- Discord text no longer lists empty rankings (e.g. "Deaths 0.0/h" when nobody died).
- Rule updates that arrive before the guild roster has loaded are applied once it loads.
- The realm day uses server time until the game calendar is ready (never the PC clock).
- An incomplete roster from the server no longer hides members from the leaderboard.
- Offline members' data is relayed to every new login (relay cooldown was too long),
  and the roster is refreshed before relaying.
- Opening a page before the main window had been shown no longer errors.

Testing
- Automated simulated-guild test suite (52 tests) on Lua 5.1 and 5.3 in GitHub Actions,
  plus an addon/Discord bot score parity check; tests run before every release.
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
