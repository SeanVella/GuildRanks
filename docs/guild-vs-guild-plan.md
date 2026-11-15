# Plan: guild vs guild leaderboards ("Guild Ranks League")

Status: **planned, not built.** The addon today compares members *within* one guild.
This document plans how guilds could compete *against each other* (per realm and
per region) without breaking Blizzard's addon rules or EU data-protection law.

## 1. Why this needs a server

An addon can only talk to players in the same guild, party or raid, and it cannot
reach the internet. Comparing guilds therefore needs a small central service (the
"Hub") that receives each guild's results and publishes the league tables, just as
Warcraft Logs and Raider.IO do with their companion apps.

## 2. How it would work

```
 Addon (in game)            Companion uploader (PC)          Guild Ranks Hub               Viewers
 ───────────────            ───────────────────────          ───────────────               ───────
 records stats  ──logout──▶ reads GuildRanks.lua  ──HTTPS──▶ API: validates, merges  ──▶  website: league tables
 shares in guild            sends weekly summary             DB: weekly guild totals  ──▶  Discord bot: weekly post
                                                             verifies guild claims
```

1. **Addon (no change in principle):** guilds that want to compete tick a new
   manager setting, *"Take part in the public league"*. Only then does the export
   include a weekly guild summary for the Hub.
2. **Companion uploader:** a small desktop tool (or the existing PowerShell script,
   extended) uploads after each session. The addon itself never goes online.
3. **Hub API:** stores weekly aggregates per guild (not raw daily data), merges
   uploads from several members of the same guild (keeping the most complete copy,
   as the GitHub template does today), and computes league standings.
4. **Website:** realm and region league tables, guild pages, past seasons.
5. **Discord bot:** a guild links a channel once; the bot posts the weekly results.
   This would replace the GitHub template for guilds that prefer zero setup.

## 3. Claiming a guild (proof that you speak for it)

A guild appears in the league only after a manager claims it:

1. The Guild Master or an officer signs in on the website and asks to claim
   `<Guild>-<Realm>`. The Hub shows a short code, for example `GR-7F3K`.
2. They put the code in the guild **message of the day** for a while.
3. The addon includes the guild's message of the day in the next upload from any
   member; when the Hub sees the code, the claim is confirmed.

Optional later: Battle.net sign-in plus Blizzard's Profile API to confirm the
claimer's rank automatically. **To verify:** whether Blizzard's web API covers
WoW: Forever guilds and rosters (it does for retail; Classic coverage has been
patchy).

## 4. Fair comparison between guilds of different sizes

- **Per-hour performance, not totals,** so big guilds don't win by headcount.
- **Guild score = average of the guild's top 10 qualified members** (members with
  the minimum play time), placed against members of every guild in the league.
- **Size divisions:** Small (5-19 active members), Medium (20-49), Large (50+),
  with at least 5 qualified members to be ranked at all.
- **Level divisions** for the levelling categories, as in the addon.
- **Seasons:** weekly standings roll up into monthly/seasonal tables with a
  "Guild of the Season".

## 5. Cheating: what we can and can't do

Stats come from players' own clients, so a determined cheater can always fake
them. The League should stay a friendly competition, never one with real prizes.
Mitigations:

- **Plausibility caps** per level (e.g. XP per hour above the theoretical maximum,
  gold per hour far above anyone else) flag a result for review.
- **Cross-checks:** several members' uploads of the same guild must agree on
  shared players' data; disagreements are flagged.
- **Officer exclusions** already in the addon carry over (excluded players don't count).
- **Moderation:** reported guilds can be hidden from public tables; every action logged.

## 6. Data protection (EU / GDPR — the operator is in Malta)

Character names linked to a guild and activity can count as personal data, so
the person running the Hub becomes the **data controller**. Before launch:

- **Opt-in only:** the guild manager opts the guild in; each member keeps the
  addon's "Share my stats" switch, and members who turn it off are never uploaded.
- **Data minimisation:** store weekly aggregates per character, no raw daily logs,
  no account or Battle.net IDs (except optional sign-in for claimers).
- **Retention:** keep weekly data for a limited time (e.g. 12 months), then delete
  or anonymise.
- **Rights:** a simple way to see and delete one's data ("delete my character").
- **Privacy policy and terms** on the website; EU hosting; data-processing
  agreement with the hosting provider.
- **Get a short legal review** (Malta IDPC guidance) before going public.

## 7. Blizzard rules

- The addon stays free, open source, with no network access and no in-game
  advertising or donation requests.
- The companion uploader and website are separate from the addon (as with
  Warcraft Logs / Raider.IO).
- If Blizzard's web API is used: follow the Blizzard Developer API Terms of Use.

## 8. Hosting and cost

- **Option A — serverless:** Cloudflare Workers + D1 (database) + Pages
  (website). Low traffic likely fits in free tiers (check current limits).
- **Option B — homelab:** the existing Proxmox host behind a Cloudflare tunnel.
  Cheapest, but the League goes down with the home connection.
- A domain name (~€10/year).

## 9. Phases

| Phase | What | Depends on |
|---|---|---|
| 0 (done) | Per-guild addon, Copy for Discord, GitHub template | — |
| 1 | Addon: "Take part in the public league" setting; weekly guild summary in the export; message-of-the-day in export | addon release |
| 2 | Hub MVP: upload API, guild claim flow, realm/region league table website | Phase 1, privacy policy |
| 3 | Discord bot for any guild (link a channel, weekly post) | Phase 2 |
| 4 | Seasons, size divisions, plausibility checks, moderation tools | Phase 2 |

## 10. Decisions needed before Phase 2

1. Hosting: serverless (A) or homelab (B)?
2. League scope: per realm only, or also whole region?
3. Name and domain for the website.
4. Who moderates, and how reports are handled.
5. Legal review of the privacy policy.
