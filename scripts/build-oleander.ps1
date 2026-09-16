[CmdletBinding()]
param(
  [string]$PrivateRoot,
  [string]$HugoPath,
  [string]$BaseURL = "https://gwokhiujin.github.io/"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
if ([string]::IsNullOrWhiteSpace($PrivateRoot)) {
  $PrivateRoot = Join-Path (Split-Path -Parent $repoRoot) "Oleander"
}
$PrivateRoot = [IO.Path]::GetFullPath($PrivateRoot)

if ($PrivateRoot.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "PrivateRoot must be outside the public repository."
}

$privateContent = Join-Path $PrivateRoot "content\Oleander"
$passwordFile = Join-Path $PrivateRoot ".password"
$buildRoot = Join-Path $PrivateRoot ".build"
$stagedContent = Join-Path $buildRoot "content"
$stagedSite = Join-Path $buildRoot "site"
$plainHtml = Join-Path $PrivateRoot "html"
$encryptedRoot = Join-Path $repoRoot "protected\Oleander"
$cryptoConfig = Join-Path $repoRoot "scripts\oleander-crypto.json"
$encryptScript = Join-Path $repoRoot "scripts\encrypt-oleander.mjs"

function Reset-SafeDirectory {
  param([string]$Path, [string]$AllowedRoot)
  $fullPath = [IO.Path]::GetFullPath($Path)
  $fullRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
  if (-not $fullPath.StartsWith("$fullRoot$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to reset directory outside $fullRoot`: $fullPath"
  }
  if (Test-Path -LiteralPath $fullPath) {
    Remove-Item -LiteralPath $fullPath -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
}

function Resolve-HugoExecutable {
  if (-not [string]::IsNullOrWhiteSpace($HugoPath)) {
    return (Resolve-Path -LiteralPath $HugoPath).Path
  }
  if (-not [string]::IsNullOrWhiteSpace($env:OLEANDER_HUGO_EXE) -and (Test-Path -LiteralPath $env:OLEANDER_HUGO_EXE)) {
    return (Resolve-Path -LiteralPath $env:OLEANDER_HUGO_EXE).Path
  }
  $installed = Get-Command hugo -ErrorAction SilentlyContinue
  if ($installed) { return $installed.Source }

  $toolRoot = Join-Path $PrivateRoot ".tools\hugo"
  $cached = Get-ChildItem -LiteralPath $toolRoot -Filter "hugo.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cached) { return $cached.FullName }

  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) {
    throw "Hugo was not found. Install Hugo Extended 0.166.0 or pass -HugoPath."
  }
  $downloadRoot = Join-Path $PrivateRoot ".tools\hugo-download"
  Reset-SafeDirectory -Path $downloadRoot -AllowedRoot $PrivateRoot
  & $winget.Source download --id Hugo.Hugo.Extended --exact --version 0.166.0 --download-directory $downloadRoot --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { throw "winget could not download Hugo." }
  $archive = Get-ChildItem -LiteralPath $downloadRoot -Filter "*.zip" -File | Select-Object -First 1
  if (-not $archive) { throw "The downloaded Hugo archive was not found." }
  Reset-SafeDirectory -Path $toolRoot -AllowedRoot $PrivateRoot
  Expand-Archive -LiteralPath $archive.FullName -DestinationPath $toolRoot -Force
  $downloaded = Get-ChildItem -LiteralPath $toolRoot -Filter "hugo.exe" -Recurse -File | Select-Object -First 1
  if (-not $downloaded) { throw "hugo.exe was not found in the downloaded archive." }
  return $downloaded.FullName
}

if (-not (Test-Path -LiteralPath $privateContent)) {
  throw "Private Oleander content was not found at $privateContent"
}
if (-not (Test-Path -LiteralPath $passwordFile)) {
  throw "Password file was not found at $passwordFile"
}

$hugo = Resolve-HugoExecutable
Reset-SafeDirectory -Path $stagedContent -AllowedRoot $PrivateRoot
Reset-SafeDirectory -Path $stagedSite -AllowedRoot $PrivateRoot
Reset-SafeDirectory -Path $plainHtml -AllowedRoot $PrivateRoot

Copy-Item -Path (Join-Path $repoRoot "content\*") -Destination $stagedContent -Recurse -Force
New-Item -ItemType Directory -Force -Path (Join-Path $stagedContent "Oleander") | Out-Null
Copy-Item -Path (Join-Path $privateContent "*") -Destination (Join-Path $stagedContent "Oleander") -Recurse -Force

& $hugo --source $repoRoot --contentDir $stagedContent --destination $stagedSite --cleanDestinationDir --baseURL $BaseURL
if ($LASTEXITCODE -ne 0) { throw "Hugo failed to build the private Oleander source." }

$builtOleander = Join-Path $stagedSite "Oleander"
$builtFiles = Get-ChildItem -LiteralPath $builtOleander -Filter "*.html" -Recurse -File
if (-not $builtFiles) { throw "Hugo did not generate any Oleander HTML files." }
foreach ($file in $builtFiles) {
  $relativePath = [IO.Path]::GetRelativePath($builtOleander, $file.FullName)
  $destination = Join-Path $plainHtml $relativePath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $destination
}

$password = (Get-Content -LiteralPath $passwordFile -Raw).Trim()
if ($password -notmatch "^[a-z]{5}$") {
  throw "The password file must contain exactly five lowercase English letters."
}

try {
  $env:OLEANDER_PASSWORD = $password
  & node $encryptScript --input $plainHtml --output $encryptedRoot --config $cryptoConfig --asset-root $stagedSite
  if ($LASTEXITCODE -ne 0) { throw "Oleander encryption failed." }
} finally {
  Remove-Item Env:OLEANDER_PASSWORD -ErrorAction SilentlyContinue
}

$encryptedFiles = Get-ChildItem -LiteralPath $encryptedRoot -Filter "*.html" -Recurse -File
if ($encryptedFiles.Count -ne $builtFiles.Count) {
  throw "Encrypted file count does not match plaintext file count."
}
foreach ($file in $encryptedFiles) {
  if ([IO.File]::ReadAllText($file.FullName).Contains($password)) {
    throw "The literal password unexpectedly appeared in $($file.FullName)."
  }
}

Write-Output "Plaintext HTML: $plainHtml"
Write-Output "Encrypted HTML: $encryptedRoot"
