[CmdletBinding()]
param(
  [switch]$Publish,
  [string]$HugoPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$dataPath = Join-Path $repoRoot "data\read_tracker.json"
$dataSourceId = "1314f970-b6c8-8168-98ba-000b7e9537f7"
$notionVersion = "2026-03-11"
$notionUri = "https://api.notion.com/v1/data_sources/$dataSourceId/query"

function Invoke-Git {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

  & git @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
}

function Resolve-HugoExecutable {
  if (-not [string]::IsNullOrWhiteSpace($HugoPath)) {
    return (Resolve-Path -LiteralPath $HugoPath).Path
  }

  $installed = Get-Command hugo -ErrorAction SilentlyContinue
  if ($installed) {
    return $installed.Source
  }

  throw "Hugo was not found. Install Hugo or pass -HugoPath with the path to hugo.exe."
}

function Get-PlainTitle {
  param($TitleProperty)

  if ($null -eq $TitleProperty) {
    return ""
  }

  $parts = foreach ($part in @($TitleProperty)) {
    if ($null -ne $part -and $null -ne $part.PSObject.Properties["plain_text"]) {
      [string]$part.plain_text
    }
  }

  return (($parts -join "") -replace "\s+", " ").Trim()
}

function Convert-EntriesToJson {
  param([System.Collections.Generic.List[object]]$Entries)

  $blocks = foreach ($entry in $Entries) {
    $dateJson = ConvertTo-Json -InputObject ([string]$entry.date) -Compress
    $titleJson = ConvertTo-Json -InputObject ([string]$entry.title) -Compress
    $ratingJson = ConvertTo-Json -InputObject ([string]$entry.rating) -Compress
    "  {`n    `"date`": $dateJson,`n    `"title`": $titleJson,`n    `"rating`": $ratingJson`n  }"
  }

  if ($blocks.Count -eq 0) {
    return "[]`n"
  }

  return "[`n$($blocks -join ",`n")`n]`n"
}

function Test-PublishPreconditions {
  Push-Location $repoRoot
  try {
    $branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to determine the current Git branch."
    }
    if ($branch -ne "main") {
      throw "Publishing is only allowed from the main branch; current branch is '$branch'."
    }

    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
      throw "The Git index already contains staged changes. Commit or unstage them before using -Publish."
    }
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to inspect staged Git changes."
    }
  } finally {
    Pop-Location
  }
}

if ($Publish) {
  Test-PublishPreconditions
}

$token = $env:NOTION_ACCESS_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
  throw "NOTION_ACCESS_TOKEN is not set. Create a Notion connection, share the Books database with it, and set the token in this environment."
}

$headers = @{
  Authorization = "Bearer $token"
  "Content-Type" = "application/json"
  "Notion-Version" = $notionVersion
}

$entries = [System.Collections.Generic.List[object]]::new()
$cursor = $null
$skipped = 0
$unrated = 0

do {
  $body = [ordered]@{
    page_size = 100
    filter = @{
      property = "Completed Date"
      date = @{ is_not_empty = $true }
    }
    sorts = @(
      @{ property = "Completed Date"; direction = "descending" },
      @{ property = "Name"; direction = "ascending" }
    )
  }

  if (-not [string]::IsNullOrWhiteSpace($cursor)) {
    $body.start_cursor = $cursor
  }

  try {
    $response = Invoke-RestMethod -Method Post -Uri $notionUri -Headers $headers -Body ($body | ConvertTo-Json -Depth 10 -Compress)
  } catch {
    throw "Notion sync failed: $($_.Exception.Message)"
  }

  foreach ($page in @($response.results)) {
    $nameProperty = $page.properties.PSObject.Properties["Name"]
    $dateProperty = $page.properties.PSObject.Properties["Completed Date"]
    $ratingProperty = $page.properties.PSObject.Properties["Rating"]
    if ($null -eq $nameProperty -or $null -eq $dateProperty -or $null -eq $ratingProperty) {
      throw "The Notion schema no longer contains the expected Name, Completed Date, and Rating properties."
    }

    $title = Get-PlainTitle $nameProperty.Value.title
    $start = if ($null -ne $dateProperty.Value.date) { [string]$dateProperty.Value.date.start } else { "" }
    $dateMatch = [regex]::Match($start, "^\d{4}-\d{2}-\d{2}")

    if ([string]::IsNullOrWhiteSpace($title) -or -not $dateMatch.Success) {
      $skipped += 1
      continue
    }

    $sourceRating = if ($null -ne $ratingProperty.Value.select) { [string]$ratingProperty.Value.select.name } else { "" }
    $sourceRatingCharacters = @($sourceRating.ToCharArray())
    $invalidRatingCharacters = @($sourceRatingCharacters | Where-Object { [int]$_ -ne 0x2605 })
    if ($sourceRatingCharacters.Count -ge 1 -and $sourceRatingCharacters.Count -le 5 -and $invalidRatingCharacters.Count -eq 0) {
      $rating = "*" * $sourceRatingCharacters.Count
    } else {
      $rating = ""
      $unrated += 1
    }

    $entries.Add([pscustomobject][ordered]@{
      date = $dateMatch.Value
      title = $title
      rating = $rating
    })
  }

  if ($response.has_more) {
    $cursor = [string]$response.next_cursor
    if ([string]::IsNullOrWhiteSpace($cursor)) {
      throw "Notion reported additional results without returning a pagination cursor."
    }
  } else {
    $cursor = $null
  }
} while (-not [string]::IsNullOrWhiteSpace($cursor))

$comparer = [System.Collections.Generic.Comparer[object]]::Create(
  [System.Comparison[object]]{
    param($left, $right)

    $dateOrder = [StringComparer]::Ordinal.Compare([string]$right.date, [string]$left.date)
    if ($dateOrder -ne 0) {
      return $dateOrder
    }
    return [StringComparer]::Ordinal.Compare([string]$left.title, [string]$right.title)
  }
)
$entries.Sort($comparer)

if ($entries.Count -eq 0) {
  throw "Notion returned no completed books; the existing snapshot was not changed."
}

$json = Convert-EntriesToJson $entries
$existing = if (Test-Path -LiteralPath $dataPath) { [IO.File]::ReadAllText($dataPath) } else { $null }
$changed = $existing -cne $json

if ($changed) {
  $temporaryPath = "$dataPath.tmp"
  try {
    [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $dataPath -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
  Write-Output "Updated data/read_tracker.json with $($entries.Count) completed book(s)."
} else {
  Write-Output "Read tracker is already current with $($entries.Count) completed book(s)."
}

if ($skipped -gt 0) {
  Write-Warning "Skipped $skipped record(s) without both a valid title and completion date."
}

if ($unrated -gt 0) {
  Write-Warning "$unrated record(s) had no valid one-to-five-star Rating value and were rendered without stars."
}

if (-not $Publish) {
  return
}

if (-not $changed) {
  Write-Output "Nothing changed; no commit or push was created."
  return
}

$hugo = Resolve-HugoExecutable
$verifyRoot = Join-Path ([IO.Path]::GetTempPath()) ("gwokhiujin-read-tracker-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $verifyRoot | Out-Null
try {
  & $hugo --source $repoRoot --destination $verifyRoot --cleanDestinationDir --baseURL "https://gwokhiujin.github.io/"
  if ($LASTEXITCODE -ne 0) {
    throw "Hugo verification build failed with exit code $LASTEXITCODE."
  }
} finally {
  if ([IO.Directory]::Exists($verifyRoot)) {
    [IO.Directory]::Delete($verifyRoot, $true)
  }
}

Push-Location $repoRoot
try {
  Invoke-Git add -- "data/read_tracker.json"

  & git diff --cached --quiet -- "data/read_tracker.json"
  if ($LASTEXITCODE -eq 0) {
    Write-Output "Nothing changed after staging; no commit or push was created."
    return
  }
  if ($LASTEXITCODE -ne 1) {
    throw "Unable to inspect the staged read tracker snapshot."
  }

  Invoke-Git commit -m "Update read tracker" -- "data/read_tracker.json"
  Invoke-Git push origin main
  Write-Output "Published the updated read tracker to main."
} finally {
  Pop-Location
}
