# Optional: automatic Discord posts (for any guild)

Every Guild Ranks user can already press **Copy for Discord** in game and paste the
results into a channel. This guide is for guilds that want results posted
**automatically**, for free, using GitHub:

- **Weekly** (Wednesday evening): last week's results: MVP, Wooden spoon if enabled,
  guild score, every ranking, weekly challenge winner and guild goal.
- **Daily** (every morning): yesterday's **Player of the day**. Optionally also the top 3
  in five rankings, the week so far (challenge leader, guild goal) and the Wooden spoon
  of the day. Days with fewer than 2 qualifying members are skipped.

How it works: WoW addons can't reach the internet, and the game saves addon data only
when you log out or `/reload`. So one or more officers' PCs run a small uploader that
sends their Guild Ranks data (which includes everything synced from the guild) to a
private GitHub repository of your guild. GitHub Actions workflows combine the uploads
and post to your Discord channel, even when the officers' PCs are off.

## 1. Create your guild's private repository

1. Create a **private** repository at https://github.com/new (e.g. `my-guild-ranks`).
2. Copy these files from the Guild Ranks repository into it:

| From (Guild Ranks repo) | To (your repo) |
|---|---|
| `automation/bot/guild_ranks_bot.py` | `bot/guild_ranks_bot.py` |
| `automation/workflow/weekly-post.yml` | `.github/workflows/weekly-post.yml` |
| `automation/workflow/daily-post.yml` | `.github/workflows/daily-post.yml` (leave out if you don't want daily posts) |
| `automation/tools/guild-ranks-upload.ps1` | keep on officers' PCs (step 4) |

3. Create an empty `uploads/` folder (add an empty `uploads/.gitkeep` file).

## 2. Add your Discord webhook and guild name

In your repository: **Settings → Secrets and variables → Actions**.

- **Secrets → New repository secret:** `DISCORD_WEBHOOK` = the webhook URL
  (Discord: channel settings → Integrations → Webhooks → New Webhook → Copy URL).
- **Variables → New repository variable:** `GUILD` = your guild as
  `GuildName-Realm` (e.g. `Froga-Firemaw`). Needed only if your officers have
  characters in more than one guild.

Optional variables:

| Variable | Default | What it does |
|---|---|---|
| `TIMEZONE` | `Europe/Malta` | Your realm's time zone |
| `POST_DAY`, `POST_TIME` | `wed`, `20:00` | When the weekly post goes out |
| `TOP_N` | `5` | Players per ranking in the weekly post |
| `DAILY_TIME` | `09:00` | When the daily post goes out (yesterday's results) |
| `DAILY_SECTIONS` | `player` | Daily post parts, comma separated: `player,top,week,spoon` |
| `DAILY_MIN_PLAYERS` | `2` | Skip the daily post when fewer members qualified |

If you change a day or time, also edit the `cron` lines (UTC) in that workflow.
To pause a post, open **Actions**, pick the workflow, then **⋯ → Disable workflow**.

## 3. Create an upload token for each officer

https://github.com/settings/personal-access-tokens/new → fine-grained token:

- Repository access: **Only select repositories** → your guild repository
- Permissions → Repository → **Contents: Read and write**
- Expiration: up to a year (set a reminder to renew)

## 4. Install the uploader on each officer's Windows PC

1. Save `guild-ranks-upload.ps1` as `C:\GuildRanks\guild-ranks-upload.ps1`, open it
   and set `$WowPath`, `$Repo` (e.g. `your-user/my-guild-ranks`) and `$Token`.
2. Test once (log out of the game first so there's data to upload):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\GuildRanks\guild-ranks-upload.ps1
Get-Content $env:LOCALAPPDATA\GuildRanks\upload.log
```

3. Run it every 15 minutes (it only uploads when something changed):

```powershell
schtasks /Create /TN "Guild Ranks upload" /SC MINUTE /MO 15 /TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\GuildRanks\guild-ranks-upload.ps1" /F
```

## 5. Test

Repository → **Actions → Guild Ranks weekly Discord post** (or **daily Discord
post**) → **Run workflow**: tick **dry run** to see the messages in the log, or
**force** to post now.

Preview on your own PC (needs Python 3.9+), after logging out of the game:

```powershell
python bot\guild_ranks_bot.py preview --sv "C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\YOUR-ACCOUNT\SavedVariables\GuildRanks.lua"
python bot\guild_ranks_bot.py preview --daily --sections player,top,week --sv "...\GuildRanks.lua"
```
