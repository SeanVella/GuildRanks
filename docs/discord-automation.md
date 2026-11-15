# Optional: automatic weekly Discord posts (for any guild)

Every Guild Ranks user can already press **Copy for Discord** in game and paste the
results into a channel. This guide is for guilds that want the weekly results
posted **automatically** every week, for free, using GitHub.

How it works: one or more officers' PCs upload their Guild Ranks data to a private
GitHub repository of your guild. Every Wednesday evening a GitHub Actions workflow
combines the uploads and posts last week's results (MVP, Wooden spoon if enabled,
guild score and every ranking) to your Discord channel.

## 1. Create your guild's private repository

1. Create a **private** repository at https://github.com/new (e.g. `my-guild-ranks`).
2. Copy these files from the Guild Ranks repository into it:

| From (Guild Ranks repo) | To (your repo) |
|---|---|
| `automation/bot/guild_ranks_bot.py` | `bot/guild_ranks_bot.py` |
| `automation/workflow/weekly-post.yml` | `.github/workflows/weekly-post.yml` |
| `automation/tools/guild-ranks-upload.ps1` | keep on officers' PCs (step 4) |

3. Create an empty `uploads/` folder (add an empty `uploads/.gitkeep` file).

## 2. Add your Discord webhook and guild name

In your repository: **Settings → Secrets and variables → Actions**.

- **Secrets → New repository secret:** `DISCORD_WEBHOOK` = the webhook URL
  (Discord: channel settings → Integrations → Webhooks → New Webhook → Copy URL).
- **Variables → New repository variable:** `GUILD` = your guild as
  `GuildName-Realm` (e.g. `Froga-Firemaw`). Needed only if your officers have
  characters in more than one guild.

Optional variables: `POST_DAY` (default `wed`), `POST_TIME` (default `20:00`),
`TIMEZONE` (default `Europe/Malta`), `TOP_N` (default `5`).
If you change the day or time, also edit the `cron` lines (UTC) in the workflow.

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

Repository → **Actions → Guild Ranks weekly Discord post → Run workflow**:
tick **dry run** to see the messages in the log, or **force** to post now.
