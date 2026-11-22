# Guild vs Guild ("Guild Ranks League")

Status: **built in 1.3.0** (sections A–F). The server-based League (section G) stays a possible
later step.

## A. What players get

- A **Guild vs Guild** tab with two views:
  - **Rivals**: up to 5 linked guilds, this week's score against each ("Froga 4.5 – 3.5 Night
    Owls"), the W–L–D record and past weeks. Click a rival for the category breakdown.
  - **All guilds**: every publicly visible guild that uses Guild Ranks, ranked by a "power"
    score (100 = best in every category), with a **Challenge** button for officers.
- Guilds are **public by default**; officers can hide theirs in Settings → Guild rules.
- **Officers** challenge other guilds; an officer of the other guild accepts or declines.
  **Challenge by name** works without the public channel.
- Cards when your guild takes or loses the lead in a match; the weekly result in the weekly
  popup, in Copy for Discord and posted once in guild chat (if the guild posts the MVP).

## B. The match

- **League week**: Wednesday to Wednesday (realm days) for every guild, so all guilds compare
  the same window whatever their own reset day.
- **8 categories**: Gold, Levels, Damage, Healing, Quests, Kills, Gathering, Crafting.
- Each category: the **average per hour of the guild's top 5 qualified players** (the guild's own
  minimum play time); the higher guild wins the point, a tie is half a point each.
- A guild needs **at least 3 qualified players** for the week to count.
- **Rivals only see category averages** and the number of players, never member names.

## C. How the data moves (no server, no website)

1. **Team sheet**: each guild's addon computes its sheet for the league week (8 averages, the
   number of qualified players and of addon users).
2. **Public league channel**: the addon joins a hidden custom channel ("GuildRanksLeague") and one
   online member per visible guild broadcasts the sheet every 10 minutes (others skip when they
   hear their own guild's sheet). Everyone listening builds the "All guilds" list. Challenges,
   answers and rivalry endings go through the channel too.
3. **Whisper fallback**: the CHANNEL chat type is disabled on Classic; if Forever blocks it too,
   officers can still challenge by typing the name of a member of the other guild, and rivals
   swap sheets by whisper with the last member they heard from (asking again when a sheet is
   more than 25 minutes old).
4. **Inside the guild**: rival links and rivals' sheets are passed to every member over the guild
   channel, so everyone sees the tab even if only one member heard the other guild.

## D. Messages (prefix GuildRanks, kind "G")

| Message | Meaning |
|---|---|
| `G;1;b;guild;week;qualified;users;v1,...,v8` | team sheet (base-36 per-hour values) |
| `G;1;c;id;from;to` | challenge (channel, whisper, or relayed in the guild) |
| `G;1;a;id;from;to;yes|no` | answer from an officer of `to` |
| `G;1;n;id;guild;officers` | whisper reply from a non-officer: who can accept |
| `G;1;u;from;to` | rivalry ended |
| `G;1;q;guild` | whisper: "send me your sheet" |
| `G;1;rv;name:since:ended,...` | rival list, shared inside the guild |
| `G;1;r;week;rival;result` | "this week's result was announced" (posted once per guild) |

## E. Fairness and abuse

- Per hour and top 5 only: small active guilds can beat big ones.
- Values are checked against plausibility caps; impossible sheets are ignored.
- Only officers (the guild's rule managers) can challenge, accept or end a rivalry.
- Stats are self-reported: friendly competition, never real prizes.

## F. Limits to check in game

- Whether Forever allows addon messages on custom channels (if not, the whisper fallback and
  the guild relay still work, but there is no automatic "All guilds" list).
- Whispers don't cross factions: matches by name are same-faction only.
- Addon messages pause during instance encounters; sheets catch up afterwards.

## G. Later: the server-based League

A companion uploader and a website ("Hub") could publish region-wide tables, guild pages and a
Discord bot. That needs hosting, a privacy policy (GDPR, operator in Malta) and a guild claim
flow (code in the guild message of the day). Not needed for the in-game version.
