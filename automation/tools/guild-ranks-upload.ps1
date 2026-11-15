# Guild Ranks uploader: sends your guild export to the GitHub repository when it changes.
# Run every 15 minutes with Task Scheduler (see README).

# ---- settings: edit these three lines ----
$WowPath = "C:\Program Files (x86)\World of Warcraft"
$Repo    = "YOUR-GITHUB-USER/your-guild-ranks"
$Token   = "github_pat_PASTE_TOKEN_HERE"
# -------------------------------------------

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Name = $env:USERNAME -replace '[^A-Za-z0-9_-]', ''
if (-not $Name) { $Name = "member" }

$stateDir = Join-Path $env:LOCALAPPDATA "GuildRanks"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$stateFile = Join-Path $stateDir "last-upload.txt"
$logFile = Join-Path $stateDir "upload.log"
function Write-Log($msg) { Add-Content -Path $logFile -Value "$(Get-Date -Format s) $msg" }

# Newest GuildRanks.lua (if you have several WoW accounts)
$pattern = Join-Path $WowPath "_forever_\WTF\Account\*\SavedVariables\GuildRanks.lua"
$file = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $file) { exit 0 }

# Pull the export (a JSON string written by the addon on logout / reload) out of the file
$raw = Get-Content -Path $file.FullName -Raw -Encoding UTF8
$m = [regex]::Match($raw, '\["exportJSON"\]\s*=\s*"((?:[^"\\]|\\.)*)"', 'Singleline')
if (-not $m.Success) { exit 0 }
$json = [regex]::Replace($m.Groups[1].Value, '\\(["\\])', '$1')
$bytes = [Text.Encoding]::UTF8.GetBytes($json)

# Only upload when the export changed
$hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes))
if ((Test-Path $stateFile) -and ((Get-Content $stateFile -Raw).Trim() -eq $hash)) { exit 0 }

$headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent"           = "GuildRanks-uploader"
}
$api = "https://api.github.com/repos/$Repo/contents/uploads/$Name.json"

try {
    # The file's current version id is needed to replace it
    $sha = $null
    try {
        $sha = (Invoke-RestMethod -Uri $api -Headers $headers -Method Get).sha
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -ne 404) { throw }
    }
    $body = @{ message = "Upload from $Name"; content = [Convert]::ToBase64String($bytes) }
    if ($sha) { $body.sha = $sha }
    Invoke-RestMethod -Uri $api -Headers $headers -Method Put -ContentType "application/json" `
        -Body ($body | ConvertTo-Json) | Out-Null
    Set-Content -Path $stateFile -Value $hash
    Write-Log "uploaded uploads/$Name.json ($([math]::Round($bytes.Length / 1KB)) KB)"
} catch {
    Write-Log "upload failed: $($_.Exception.Message)"
    exit 1
}
