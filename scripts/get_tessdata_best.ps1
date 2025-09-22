<#
.SYNOPSIS
  Download selected Tesseract language files from tessdata_best and prepare the folder.

.DESCRIPTION
  Fetches .traineddata files from the official GitHub repo:
    https://github.com/tesseract-ocr/tessdata_best
  Creates the destination folder if needed and (optionally) sets TESSDATA_PREFIX.

.PARAMETER DestDir
  Destination folder for the language files (e.g., C:\Tesseract\tessdata_best).

.PARAMETER Langs
  Language codes to download (default: deu, eng, osd).

.PARAMETER MaxRetries
  Max retry attempts for each download (default: 3).

.PARAMETER Force
  Overwrite existing files.

.PARAMETER SetTessdataPrefix
  Attempt to set TESSDATA_PREFIX (User scope) to the parent of DestDir (e.g., C:\Tesseract).
  Tesseract will then find languages in %TESSDATA_PREFIX%\tessdata_best.
  Note: Your OCR script already uses --tessdata-dir if the folder exists, so this is optional.

.EXAMPLE
  .\get_tessdata_best.ps1

.EXAMPLE
  .\get_tessdata_best.ps1 -DestDir "C:\Tesseract\tessdata_best" -Langs deu,eng,osd

.EXAMPLE
  .\get_tessdata_best.ps1 -DestDir "D:\Apps\Tesseract\tessdata_best" -Langs deu,eng -Force

.EXAMPLE
  .\get_tessdata_best.ps1 -SetTessdataPrefix

#>

param(
  [string]$DestDir = "C:\Tesseract\tessdata_best",
  [string[]]$Langs = @("deu","eng","osd"),
  [int]$MaxRetries = 3,
  [switch]$Force,
  [switch]$SetTessdataPrefix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor DarkGray }
function Write-Warn($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Ok($msg)  { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Err($msg) { Write-Host "[ERR]  $msg" -ForegroundColor Red }

$baseUrl = "https://github.com/tesseract-ocr/tessdata_best/raw/main"

if (-not (Test-Path $DestDir)) {
  Write-Info "Creating destination folder: $DestDir"
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
}

function Get-FileSha256([string]$Path){
  if (-not (Test-Path $Path)) { return $null }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $fs  = [System.IO.File]::OpenRead($Path)
  try {
    ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally {
    $fs.Dispose(); $sha.Dispose()
  }
}

foreach($lang in $Langs){
  $name = "$lang.traineddata"
  $url  = "$baseUrl/$name"
  $out  = Join-Path $DestDir $name

  if ((Test-Path $out) -and -not $Force) {
    Write-Info "$name already exists (use -Force to overwrite)."
    continue
  }

  $ok = $false
  for($i=1; $i -le $MaxRetries; $i++){
    try {
      Write-Info "Downloading $name (attempt $i/$MaxRetries)..."
      $tmp = "$out.download"
      if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
      Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 120
      Move-Item $tmp $out -Force
      $ok = $true
      break
    } catch {
      Write-Warn "Download failed: $($_.Exception.Message)"
      Start-Sleep -Seconds ([Math]::Min(5*$i, 15))
    }
  }

  if (-not $ok) {
    Write-Err "Giving up on $name"
    continue
  }

  $size = (Get-Item $out).Length
  $hash = Get-FileSha256 $out
  Write-Ok ("Saved {0}  ({1:N0} bytes)  sha256={2}" -f $name, $size, $hash)
}

# Optionally set TESSDATA_PREFIX for current user
if ($SetTessdataPrefix) {
  try {
    $parent = Split-Path -Path $DestDir -Parent
    if (-not $parent) { $parent = $DestDir }
    [Environment]::SetEnvironmentVariable("TESSDATA_PREFIX", $parent, "User")
    Write-Ok "Set TESSDATA_PREFIX (User) to: $parent"
    Write-Info "Restart your shell to ensure the variable is available."
  } catch {
    Write-Warn "Could not set TESSDATA_PREFIX: $($_.Exception.Message)"
  }
}

# Optional verification step: try listing languages with tesseract (if present)
try {
  $tess = (Get-Command tesseract -ErrorAction Stop).Source
  Write-Info "Found tesseract: $tess"
  $dirQuoted = '"' + $DestDir + '"'
  Write-Info "Verifying installed languages via: tesseract --tessdata-dir $dirQuoted --list-langs"
  & tesseract --tessdata-dir $DestDir --list-langs
} catch {
  Write-Warn "tesseract not found in PATH (verification step skipped)."
}

Write-Ok "All done."
