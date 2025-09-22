<#
.SYNOPSIS
  OCR (Tesseract) -> TXT/TSV -> Fusion mit Vision-Sidecar (.md) -> JSON/RAG Sidecars.
  ASCII-only Logs (keine Sonderzeichen), PowerShell 5+ kompatibel.

.DESCRIPTION
  - Preprocessing (ImageMagick oder .NET Fallback)
  - Erster OCR-Pass (deu, psm konfigurierbar)
  - Fallback-Suche über PSM/Sprachen, Scoring via Wort-Konfidenzen
  - Merge mit Vision-Markdown (Frontmatter + "Zweck"/"Sichtbare UI-Elemente")
  - Outputs: .json, .rag.txt, .norm.txt, ocr_tmp\<name>.txt/.tsv

.NOTES
  - JSON wird als UTF-8 (ohne BOM) geschrieben
  - Erzeugt: captions\ocr_tmp\<name>.txt/.tsv, captions\<name>.json, captions\<name>.norm.txt, captions\<name>.rag.txt
#>

param(
  [string]$BaseDir = "D:\KI\OpenWebUI\docs\screenshots",

  # statt [bool]... :
  [switch]$UsePreprocess,
  [switch]$NoPreprocess,

  [string]$TessDataBest = "C:\Tesseract\tessdata_best",
  [string]$LangPrimary = "deu",
  [string]$LangMixed = "deu+eng",

  # statt [bool]... :
  [switch]$TryMixedLang,
  [switch]$NoMixedLang,

  [int]$TessOEM = 3,
  [int]$TessPSM = 6,
  [int[]]$PsmCandidates = @(6, 12, 3, 4, 11, 7),
  [int]$MinConfTarget = 60,
  [int]$MinConfForBlocks = 50,
  [int]$MaxBlocksToKeep = 5000,
  [string[]]$ImagePatterns = @("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tif", "*.tiff")
)

# Defaults: Preprocess = ON, MixedLang = ON (wie bisher)
$UsePreprocessEff = if ($PSBoundParameters.ContainsKey('UsePreprocess')) { $true }
elseif ($PSBoundParameters.ContainsKey('NoPreprocess')) { $false }
else { $false }

$TryMixedEff = if ($PSBoundParameters.ContainsKey('TryMixedLang')) { $true }
elseif ($PSBoundParameters.ContainsKey('NoMixedLang')) { $false }
else { $true }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- ImageMagick Lazy-Init --------------------------------------------------
$script:Magick = $null
$script:MagickChecked = $false

# Optionaler fester Pfad (anpassen, falls nötig)
$MagickExeOverride = "C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe"
if (Test-Path $MagickExeOverride) { $script:Magick = $MagickExeOverride; $script:MagickChecked = $true }

function Resolve-Magick {
  if ($script:MagickChecked) { return }
  try { $script:Magick = (Get-Command magick.exe -ErrorAction Stop).Source } catch { $script:Magick = $null }
  if (-not $script:Magick) {
    $cands = @(
      "C:\Program Files\ImageMagick-7*\magick.exe",
      "C:\ProgramData\chocolatey\bin\magick.exe"
    ) | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } | Sort-Object FullName -Descending
    if ($cands -and $cands.Count) { $script:Magick = $cands[0].FullName }
  }
  $script:MagickChecked = $true
}

# --- Konfiguration -----------------------------------------------------------
$RawDir = Join-Path $BaseDir "raw"
$CaptionsDir = Join-Path $BaseDir "captions"
$OcrTmpDir = Join-Path $CaptionsDir "ocr_tmp"

# tessdata_best
$UseBest = $false
if ($TessDataBest -and (Test-Path $TessDataBest)) { $UseBest = $true }

# Ordner sicherstellen
if (-not (Test-Path $CaptionsDir)) { New-Item -ItemType Directory -Path $CaptionsDir | Out-Null }
if (-not (Test-Path $OcrTmpDir)) { New-Item -ItemType Directory -Path $OcrTmpDir   | Out-Null }

Write-Host ("[DIR] RAW={0} | CAPTIONS={1} | OCR_TMP={2}" -f $RawDir, $CaptionsDir, $OcrTmpDir) -ForegroundColor DarkGray

# --- PreProcess --------------------------------------------------------------
function Preprocess-Image {
  param(
    [Parameter(Mandatory = $true)][string]$InPath,
    [Parameter(Mandatory = $true)][string]$OutPath
  )

  Resolve-Magick
  if ($script:Magick) {
    Write-Host "[INFO] Using ImageMagick: $script:Magick" -ForegroundColor DarkGray
  }
  else {
    Write-Host "[INFO] ImageMagick not found - using .NET fallback preprocessor." -ForegroundColor Yellow
  }

  try {
    if ($script:Magick) {
      $magickArgs = @(
        $InPath,
        "-units", "PixelsPerInch", "-density", "300",
        "-colorspace", "Gray",
        "-resize", "200%",
        "-sigmoidal-contrast", "5x50%",
        "-unsharp", "0x0.5",
        $OutPath
      )
      & $script:Magick @magickArgs | Out-Null
    }
    else {
      Add-Type -AssemblyName System.Drawing
      $src = [System.Drawing.Image]::FromFile($InPath)
      $newW = [int]([Math]::Round($src.Width * 2.0))
      $newH = [int]([Math]::Round($src.Height * 2.0))
      $bmp = New-Object System.Drawing.Bitmap $newW, $newH
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($src, 0, 0, $newW, $newH)
      $g.Dispose(); $src.Dispose()
      $bmp.SetResolution(300, 300)
      $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
      $bmp.Dispose()
    }
  }
  catch {
    Write-Host "  [WARN] Preprocess failed, copying original image." -ForegroundColor Yellow
    Copy-Item $InPath $OutPath -Force
  }

  if (-not (Test-Path $OutPath)) { Copy-Item $InPath $OutPath -Force }
}

# --- Robust Helper to avoid '-and' parsing issues ----------------------------
function Test-TextAndTsv {
  param(
    [Parameter(Mandatory = $true)][string]$Txt,
    [Parameter(Mandatory = $true)][string]$Tsv
  )
  return (Test-Path -LiteralPath $Txt) -and (Test-Path -LiteralPath $Tsv)
}

# --- Tesseract Runner (patched) ----------------------------------------------
function Run-Tess {
  param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][string]$OutBase,
    [Parameter(Mandatory = $true)][string]$Lang,
    [Parameter(Mandatory = $true)][int]$Psm,
    [int]$Oem = 3,
    [switch]$Tsv
  )

  # Output-basename ohne Extension
  # $baseNoExt = [System.IO.Path]::ChangeExtension($OutBase, $null)
  $baseNoExt = $OutBase
  # Write-Host "baseNoExt: '$baseNoExt'"

  # Ausgabeordner sicherstellen
  $outDir = [System.IO.Path]::GetDirectoryName($baseNoExt)
  if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  }

  if (-not (Test-Path $Image)) {
    throw "Input image not found: $Image"
  }

  # Argumente in Tesseract-Reihenfolge: input, outputbase, dann Optionen
  $args = @()
  $args += @($Image, $baseNoExt)

  if ($UseBest -and (Test-Path $TessDataBest)) {
    $args += @("--tessdata-dir", $TessDataBest)
  }

  $args += @(
    "-l", $Lang,
    "--oem", $Oem,
    "--psm", $Psm,
    "-c", "preserve_interword_spaces=1",
    "-c", "user_defined_dpi=300",
    "-c", "load_system_dawg=0",
    "-c", "load_freq_dawg=0",
    "-c", "thresholding_method=2"
  )

  if ($Tsv) {
    # TSV ohne 'tsv'-Configdatei (robust gegenüber tessdata_best ohne configs/tsv)
    $args += @("-c", "tessedit_create_tsv=1")
  }

  & tesseract @args | Out-Null
}

# --- Helpers -----------------------------------------------------------------

function Convert-TsvToCleanOcrText {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$TsvPath,
    [int]$MinConf = 50,
    [int]$MaxConsecutivePunct = 2
  )

  if (-not (Test-Path -LiteralPath $TsvPath)) { return "" }

  $ci = [System.Globalization.CultureInfo]::InvariantCulture
  $tsv = Import-Csv -LiteralPath $TsvPath -Delimiter "`t"

  # Keine Nicht-ASCII-Literale verwenden:
  $EURO = "`u{20AC}"  # €
  $charClassNotAllowed = "[^\w${EURO}%/\-\+\.,:;@()&#]"        # erlaubt: \w, €, %, / - + . , : ; @ ( ) & #
  $zwChars = [string][char]0x200B + [char]0x200C + [char]0x200D + [char]0xFEFF
  $zwPattern = "[$zwChars]"
  $punctPattern = "([^\w\s])\1{$($MaxConsecutivePunct),}"
  $shortWhitelist = @($EURO, '%', 'kg', 'g', 'l', 'ml', 'St', 'Nr', 'ID', 'OK')

  # Nur echte Wörter mit conf >= MinConf
  $words = $tsv | Where-Object {
    ($_.'word_num' -as [int]) -gt 0 -and
    ([double]::Parse($_.'conf', $ci)) -ge $MinConf
  }
  if (-not $words) { return "" }

  # Lesereihenfolge
  $words = $words | Sort-Object page_num, block_num, par_num, line_num, word_num

  $lines = @()
  $currentKey = $null
  $buffer = @()
  $joinNext = $false

  foreach ($w in $words) {
    $key = "{0}-{1}-{2}-{3}" -f $w.page_num, $w.block_num, $w.par_num, $w.line_num
    if ($key -ne $currentKey) {
      if ($buffer.Count -gt 0) {
        $line = ($buffer -join " ").Trim() -replace "\s+", " "
        if ($line -match '\w') { $lines += $line }
        $buffer = @()
      }
      $currentKey = $key
      $joinNext = $false
    }

    $raw = [string]$w.text
    if (-not $raw) { continue }

    # Clean token
    $t = $raw.Normalize([Text.NormalizationForm]::FormKC)
    $t = $t -replace $zwPattern, ""
    $t = $t -replace "\s+", " "
    $t = $t -replace $charClassNotAllowed, " "
    $t = $t -replace $punctPattern, '$1$1'
    $t = $t.Trim()
    if ($t.Length -eq 0) { continue }

    # kurze Einzelzeichen droppen (ausser Ziffern/Whitelist)
    $keepShort = ($t.Length -gt 1) -or ($t -match '^\d$') -or ($shortWhitelist -contains $t)
    if (-not $keepShort) { continue }

    # Silbentrennung: wenn ORIGINAL mit '-' endete, nächstes Wort direkt anhängen
    $endsHyphen = $raw.EndsWith('-')
    if ($endsHyphen) { $t = $t.TrimEnd('-') }

    if ($joinNext -and $buffer.Count -gt 0) {
      $buffer[-1] = $buffer[-1] + $t
    }
    else {
      $buffer += $t
    }
    $joinNext = $endsHyphen
  }

  # letzte Zeile flushen
  if ($buffer.Count -gt 0) {
    $line = ($buffer -join " ").Trim() -replace "\s+", " "
    if ($line -match '\w') { $lines += $line }
  }

  return (($lines | Where-Object { $_ -match '\w' }) -join "`r`n").Trim()
}


function Get-OcrConfidenceStats {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$TsvPath,
    [int]$MinConfForBlocks = 50
  )

  if (-not (Test-Path $TsvPath)) {
    return [pscustomobject]@{
      WordCount     = 0
      AvgAll        = 0.0
      AvgFiltered   = 0.0
      ZeroShare     = 0.0
      ValidConfList = @()
    }
  }

  $ci = [System.Globalization.CultureInfo]::InvariantCulture
  $tsv = Import-Csv -LiteralPath $TsvPath -Delimiter "`t"

  # Nur echte Wort-Zeilen (word_num > 0) und conf >= 0
  $wordRows = $tsv | Where-Object {
    ($_.'word_num' -as [int]) -gt 0 -and
    ([double]::Parse($_.'conf', $ci)) -ge 0
  }

  if (-not $wordRows -or $wordRows.Count -eq 0) {
    return [pscustomobject]@{
      WordCount     = 0
      AvgAll        = 0.0
      AvgFiltered   = 0.0
      ZeroShare     = 0.0
      ValidConfList = @()
    }
  }

  $confVals = foreach ($r in $wordRows) {
    [double]::Parse($r.'conf', $ci)
  }

  $avgAll = ($confVals | Measure-Object -Average).Average
  $filtered = $confVals | Where-Object { $_ -ge $MinConfForBlocks }
  $avgFiltered = if ($filtered.Count -gt 0) { ($filtered | Measure-Object -Average).Average } else { 0.0 }
  $zeroShare = (($confVals | Where-Object { $_ -eq 0 }).Count / $confVals.Count)

  [pscustomobject]@{
    WordCount     = $confVals.Count
    AvgAll        = [math]::Round($avgAll, 2)
    AvgFiltered   = [math]::Round($avgFiltered, 2)
    ZeroShare     = [math]::Round($zeroShare, 4)
    ValidConfList = $confVals
  }
}

function Get-ImageSize {
  param([string]$Path)
  try {
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($Path)
    $w = $img.Width; $h = $img.Height
    $img.Dispose()
    return @{ width = $w; height = $h }
  }
  catch { return @{ width = $null; height = $null } }
}

function Get-FileSha1 {
  param([string]$Path)
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  $fs = [System.IO.File]::OpenRead($Path)
  try {
    $hash = $sha1.ComputeHash($fs)
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    return "sha1:$hex"
  }
  finally {
    $fs.Dispose()
    $sha1.Dispose()
  }
}

function Parse-Tsv {
  param([string]$TsvPath)
  if (-not (Test-Path $TsvPath)) { return @() }

  $rows = @()
  $header = $null

  foreach ($line in (Get-Content -LiteralPath $TsvPath -Encoding UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -like "level*") { $header = $line -split "`t"; continue }
    if (-not $header) { continue }

    $cols = $line -split "`t", $header.Count
    $obj = [ordered]@{}
    for ($i = 0; $i -lt $header.Count; $i++) { $obj[$header[$i]] = $cols[$i] }
    $rows += [pscustomobject]$obj
  }

  $mapLevel = @{ '1' = 'page'; '2' = 'block'; '3' = 'para'; '4' = 'line'; '5' = 'word' }
  $blocks = @()

  foreach ($r in $rows) {
    $text = $r.text
    if ([string]::IsNullOrWhiteSpace($text)) { continue }

    [int]$conf = 0; [void][int]::TryParse($r.conf, [ref]$conf)
    [int]$x = 0; [void][int]::TryParse($r.left, [ref]$x)
    [int]$y = 0; [void][int]::TryParse($r.top, [ref]$y)
    [int]$w = 0; [void][int]::TryParse($r.width, [ref]$w)
    [int]$h = 0; [void][int]::TryParse($r.height, [ref]$h)
    $lvl = $mapLevel[[string]$r.level]; if (-not $lvl) { $lvl = 'word' }

    $blocks += [pscustomobject]@{
      text     = $text
      conf     = $conf
      bbox     = @($x, $y, $w, $h)
      level    = $lvl
      page_num = [int]$r.page_num
    }
  }

  return $blocks
}

function Read-VisionFrontmatter {
  param([string]$MarkdownPath)
  if (-not (Test-Path $MarkdownPath)) { return $null }

  $lines = Get-Content -LiteralPath $MarkdownPath -Encoding UTF8
  $fmMarkers = $lines | Select-String -Pattern '^\s*---\s*$'
  if ($fmMarkers.Count -lt 2) { return $null }
  $startIdx = $fmMarkers[0].LineNumber - 1
  $endIdx = $fmMarkers[1].LineNumber - 1
  if ($endIdx -le $startIdx) { return $null }

  $yaml = $lines[($startIdx + 1)..($endIdx - 1)] -join "`n"

  $obj = @{
    module      = $null
    screen      = $null
    view        = $null
    tags        = @()
    captured_at = $null
    image       = $null
    source_file = $null
  }

  if ($yaml -match "(?m)^module:\s*""?([^""]+)""?\s*$") { $obj.module = $matches[1] }
  if ($yaml -match "(?m)^screen:\s*""?([^""]+)""?\s*$") { $obj.screen = $matches[1] }
  if ($yaml -match "(?m)^view:\s*""?([^""]+)""?\s*$") { $obj.view = $matches[1] }
  if ($yaml -match "(?m)^captured_at:\s*""?([^""]+)""?\s*$") { $obj.captured_at = $matches[1] }
  if ($yaml -match "(?m)^image:\s*""?([^""]+)""?\s*$") { $obj.image = $matches[1] }
  if ($yaml -match "(?m)^source_file:\s*""?([^""]+)""?\s*$") { $obj.source_file = $matches[1] }

  if ($yaml -match "(?ms)^tags:\s*\[([^\]]*)\]") {
    $raw = $matches[1]
    $tags = ($raw -split ",") | ForEach-Object {
      $_.Trim() -replace '^\s*"?', '' -replace '"?\s*$', ''
    } | Where-Object { $_ -ne "" }
    $obj.tags = $tags
  }

  return $obj
}

function Extract-VisionSummary {
  param([string]$MarkdownPath)

  $vision = @{
    summary     = $null
    ui_elements = @()
    tags        = @()
  }
  if (-not (Test-Path $MarkdownPath)) { return $vision }

  $raw = Get-Content -LiteralPath $MarkdownPath -Raw -Encoding UTF8
  if ($raw -match "(?s)^\s*---\s*.*?\s*---\s*") { $raw = $raw.Substring($matches[0].Length) }
  $lines = $raw -split "`r?`n"

  $summary = $null
  foreach ($line in $lines) {
    if ($line -match '^\s*(?:#{1,6}\s*)?(?:\*\*)?Zweck(?:\*\*)?\s*:\s*(.+)\s*$') { $summary = $matches[1].Trim(); break }
  }

  $ui = @()
  for ($i = 0; $i -lt $lines.Length; $i++) {
    $l = $lines[$i]
    if ($l -match '^\s*(?:#{1,6}\s*)?Sichtbare\s+UI(?:-Elemente)?\s*:?\s*$') {
      if ($i + 1 -lt $lines.Length -and $lines[$i + 1] -match '^\s*[-=]{3,}\s*$') { $i++ }
      for ($j = $i + 1; $j -lt $lines.Length; $j++) {
        $b = $lines[$j]
        if ($b -match '^\s*$' -or $b -match '^\s*#{1,6}\s+') { break }
        if ($b -match '^\s*[-*+]\s+(.*\S)\s*$') { $ui += $matches[1].Trim() }
      }
      break
    }
  }

  $vision.summary = $summary
  $vision.ui_elements = $ui
  return $vision
}

function Strip-Markdown([string]$s) {
  if (-not $s) { return $s }
  $s = $s -replace '\*\*', '' -replace '\*', '' -replace '_', ''
  $s = $s -replace '\[(.*?)\]\((.*?)\)', '$1'
  $s = $s -replace '`', ''
  $s.Trim()
}

# --- JSON Writer (optional Plainify) -----------------------------------------
function ConvertTo-PlainObject {
  param([Parameter(ValueFromPipeline = $true)] $InputObject)
  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [string] -or $InputObject -is [bool] -or
    $InputObject -is [int] -or $InputObject -is [long] -or
    $InputObject -is [double] -or $InputObject -is [decimal]) { return $InputObject }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $ht = @{}; foreach ($k in $InputObject.Keys) { $ht[$k] = ConvertTo-PlainObject $InputObject[$k] }; return $ht
  }
  if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
    $arr = @(); foreach ($item in $InputObject) { $arr += , (ConvertTo-PlainObject $item) }; return $arr
  }
  if ($InputObject -is [psobject]) {
    $props = $InputObject.PSObject.Properties | Where-Object { $_.MemberType -in 'NoteProperty', 'Property' }
    if ($props.Count -gt 0) { $ht = @{}; foreach ($p in $props) { $ht[$p.Name] = ConvertTo-PlainObject $p.Value }; return $ht }
  }
  return [string]$InputObject
}

function Save-JsonUtf8 {
  param([object]$Object, [string]$Path)
  Write-Host "  Writing JSON..." -ForegroundColor DarkGray
  $t = [Diagnostics.Stopwatch]::StartNew()
  $plain = ConvertTo-PlainObject $Object
  try {
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    $json = $ser.Serialize($plain)
  }
  catch {
    $json = $plain | ConvertTo-Json -Depth 12 -Compress:$true
  }
  [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
  $t.Stop()
  Write-Host ("  JSON saved in {0:N1}s -> {1}" -f $t.Elapsed.TotalSeconds, $Path) -ForegroundColor DarkGray
}

# --- manueller JSON Writer ---------------------------------------------------
function J-Escape([string]$s) {
  if ($null -eq $s) {
    return ""
  }
  $s = $s -replace '\\', '\\\\'
  $s = $s -replace '"', '\"'
  $s = $s -replace "`r", '\r'
  $s = $s -replace "`n", '\n'
  $s = $s -replace "`t", '\t'
  return $s
}
function J-Str($v) { if ($null -eq $v) { return 'null' } return '"' + (J-Escape ([string]$v)) + '"' }
function J-ArrStr([object[]]$arr) {
  if ($null -eq $arr -or $arr.Count -eq 0) { return '[]' }
  $items = @(); foreach ($a in $arr) { $items += (J-Str $a) }; return '[' + ($items -join ',') + ']'
}
function Write-SidecarJsonManual {
  param(
    [string]$Path,
    [string]$Image, [string]$Module, [string]$Screen, [string]$View,
    [string]$CapturedAt, [string]$SourceFile,
    [string]$Lang, [int]$Oem, [int]$Psm, [string]$OcrText, [int]$ConfAvg, [int]$ConfAvgAll,
    [string]$Summary, [object[]]$UiElements, [object[]]$Tags,
    [string]$Hash, [int]$Width, [int]$Height
  )
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('{')
  [void]$sb.AppendLine('  "image": ' + (J-Str $Image) + ',')
  [void]$sb.AppendLine('  "module": ' + (J-Str $Module) + ',')
  [void]$sb.AppendLine('  "screen": ' + (J-Str $Screen) + ',')
  [void]$sb.AppendLine('  "view": ' + (J-Str $View) + ',')
  [void]$sb.AppendLine('  "captured_at": ' + (J-Str $CapturedAt) + ',')
  [void]$sb.AppendLine('  "source_file": ' + (J-Str $SourceFile) + ',')
  [void]$sb.AppendLine('  "ocr": {')
  [void]$sb.AppendLine('    "lang": ' + (J-Str $Lang) + ',')
  [void]$sb.AppendLine('    "oem": ' + $Oem + ',')
  [void]$sb.AppendLine('    "psm": ' + $Psm + ',')
  [void]$sb.AppendLine('    "text": ' + (J-Str $OcrText) + ',')
  [void]$sb.AppendLine('    "conf_avg": ' + $ConfAvg + ',')
  [void]$sb.AppendLine('    "conf_avg_all": ' + $ConfAvgAll)
  [void]$sb.AppendLine('  },')
  [void]$sb.AppendLine('  "vision": {')
  [void]$sb.AppendLine('    "summary": ' + (J-Str $Summary) + ',')
  [void]$sb.AppendLine('    "ui_elements": ' + (J-ArrStr $UiElements) + ',')
  [void]$sb.AppendLine('    "tags": ' + (J-ArrStr $Tags))
  [void]$sb.AppendLine('  },')
  [void]$sb.AppendLine('  "meta": {')
  [void]$sb.AppendLine('    "hash": ' + (J-Str $Hash) + ',')
  [void]$sb.AppendLine('    "width": ' + $Width + ',')
  [void]$sb.AppendLine('    "height": ' + $Height)
  [void]$sb.AppendLine('  }')
  [void]$sb.AppendLine('}')
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $sb.ToString(), $utf8)
}

# --- Pipeline ----------------------------------------------------------------
$images = @()
foreach ($pat in $ImagePatterns) { $images += Get-ChildItem -LiteralPath $RawDir -Recurse -File -Filter $pat }
if ($images.Count -eq 0) { Write-Host "No images found in: $RawDir" -ForegroundColor Yellow; exit 0 }

$idx = 0; $tot = $images.Count

foreach ($img in $images) {
  $idx++
  try {
  $basename = [IO.Path]::GetFileNameWithoutExtension($img.Name).TrimEnd('.')
    Write-Host ("[OCR] ({0}/{1}) Start: {2}" -f $idx, $tot, $img.FullName) -ForegroundColor Cyan

    # Preprocess
    $prePath = $img.FullName
    if ($UsePreprocessEff) {
      $prePath = Join-Path $OcrTmpDir ($basename + ".pre.png")
      Preprocess-Image -InPath $img.FullName -OutPath $prePath
    }

    # First pass
    $outBase = Join-Path $OcrTmpDir $basename
    Run-Tess -Image $prePath -OutBase $outBase -Lang $LangPrimary -Psm $TessPSM -Oem $TessOEM
    Run-Tess -Image $prePath -OutBase $outBase -Lang $LangPrimary -Psm $TessPSM -Tsv -Oem $TessOEM
    Write-Host ("[OCR] First pass: lang={0}, psm={1}" -f $LangPrimary, $TessPSM) -ForegroundColor DarkGray

    # Read results (robust, culture-invariant)
    $txtPath = "$outBase.txt"; $tsvPath = "$outBase.tsv"
    # Write-Host "basename: '$basename'"
    # Write-Host "outbase: '$outBase'"
    # Write-Host "txtPath: '$txtPath'"
    if (-not (Test-Path -LiteralPath $txtPath)) {
      Write-Host "[WARN] No TXT produced - skipping file." -ForegroundColor Yellow
      continue
    }

    # Rohtext ggf. weiterhin für Debug/JSON behalten:
    $ocrTextRaw = Get-Content -LiteralPath $txtPath -Raw -Encoding UTF8

    # >>> NEU: bereinigter OCR-Text aus TSV (Confidence-geführt)
    $ocrText = Convert-TsvToCleanOcrText -TsvPath $tsvPath -MinConf $MinConfForBlocks
    if ([string]::IsNullOrWhiteSpace($ocrText)) { $ocrText = $ocrTextRaw }

    # Confidence-Stats
    $confAvgAll = 0; $confAvg = 0; $wordCount = 0; $zeroShare = 0.0
    if (Test-Path -LiteralPath $tsvPath) {
      $ci = [System.Globalization.CultureInfo]::InvariantCulture
      $tsv = Import-Csv -LiteralPath $tsvPath -Delimiter "`t"

      # Nur echte Wort-Zeilen (word_num > 0), conf >= 0
      $wordRows = $tsv | Where-Object {
        ($_.'word_num' -as [int]) -gt 0 -and
        ([double]::Parse($_.'conf', $ci)) -ge 0
      }

      if ($wordRows -and $wordRows.Count -gt 0) {
        $confVals = foreach ($r in $wordRows) { [double]::Parse($r.'conf', $ci) }

        $wordCount = $confVals.Count
        $confAvgAll = [math]::Round( ($confVals | Measure-Object -Average).Average )
        $good = $confVals | Where-Object { $_ -ge $MinConfForBlocks }
        if ($good.Count -gt $MaxBlocksToKeep) { $good = $good | Select-Object -First $MaxBlocksToKeep }
        $confAvg = if ($good.Count -gt 0) { [math]::Round( ($good | Measure-Object -Average).Average ) } else { 0 }
        $zeroShare = (($confVals | Where-Object { $_ -eq 0 }).Count / [double]$wordCount)
      }
    }

    Write-Host ("  conf_avg_all={0}, conf_avg_filtered={1} (words={2}, zero={3:P1})" -f `
        $confAvgAll, $confAvg, $wordCount, $zeroShare) -ForegroundColor DarkGray

    # Fallback search
    $chosenLang = $LangPrimary; $chosenPsm = $TessPSM
    if ($confAvgAll -lt $MinConfTarget) {
      Write-Host ("  Low quality -> fallback search (target {0})..." -f $MinConfTarget) -ForegroundColor Yellow

      # --- INITIAL BEST: immer MIT txtClean anlegen ---
      $best_txtClean = Convert-TsvToCleanOcrText -TsvPath $tsvPath -MinConf $MinConfForBlocks
      if ([string]::IsNullOrWhiteSpace($best_txtClean)) { $best_txtClean = $ocrText }   # falls TSV leer → auf aktuellen Text zurückfallen

      $best = [pscustomobject]@{
        confUsed = $confAvg
        confAll  = $confAvgAll
        lang     = $LangPrimary
        psm      = $TessPSM
        txt      = $ocrTextRaw     # Rohtext (nur Debug)
        txtClean = $best_txtClean  # Bereinigter Text
        tsv      = $tsvPath
      }

      $langs = @($LangPrimary); if ($TryMixedEff) { $langs += $LangMixed }

      foreach ($psm in $PsmCandidates) {
        foreach ($lang in $langs) {
          $tryBase = Join-Path $OcrTmpDir ($basename + ".try_" + ($lang -replace '\+', '_') + "_psm" + $psm)
          Run-Tess -Image $prePath -OutBase $tryBase -Lang $lang -Psm $psm -Oem $TessOEM
          Run-Tess -Image $prePath -OutBase $tryBase -Lang $lang -Psm $psm -Tsv -Oem $TessOEM

          $tTxt = "$tryBase.txt"; $tTsv = "$tryBase.tsv"
          $hasTry = Test-TextAndTsv -Txt $tTxt -Tsv $tTsv
          if (-not $hasTry) { continue }

          # Text laden und Conf berechnen
          $tText = Get-Content -LiteralPath $tTxt -Raw -Encoding UTF8
          $tBlocksAll = @( Parse-Tsv -TsvPath $tTsv )
          $tWords = @($tBlocksAll | Where-Object { $_.level -eq 'word' })
          $tConfAll = if ($tWords.Count) { [int]([Math]::Round((($tWords | Measure-Object conf -Average).Average))) } else { 0 }
          $tUsed = @($tWords | Where-Object { $_.conf -ge $MinConfForBlocks })
          if ($tUsed.Count -gt $MaxBlocksToKeep) { $tUsed = @($tUsed | Select-Object -First $MaxBlocksToKeep) }
          $tConfUsed = if ($tUsed.Count) { [int]([Math]::Round((($tUsed | Measure-Object conf -Average).Average))) } else { 0 }

          # Clean-Text aus TSV
          $tClean = Convert-TsvToCleanOcrText -TsvPath $tTsv -MinConf $MinConfForBlocks
          if ([string]::IsNullOrWhiteSpace($tClean)) { $tClean = $tText }

          $isBetter = ($tConfUsed -gt $best.confUsed) -or (($tConfUsed -eq $best.confUsed) -and ($tConfAll -gt $best.confAll))
          if ($isBetter) {
            $best = [pscustomobject]@{
              confUsed = $tConfUsed
              confAll  = $tConfAll
              lang     = $lang
              psm      = $psm
              txt      = $tText
              txtClean = $tClean
              tsv      = $tTsv
            }
          }
        }
      }

      if ( ($best.confUsed -gt $confAvg) -or (($best.confUsed -eq $confAvg) -and ($best.confAll -gt $confAvgAll)) ) {
        Write-Host ("  Fallback chosen: lang={0}, psm={1}, conf_used={2}, conf_all={3}" -f $best.lang, $best.psm, $best.confUsed, $best.confAll) -ForegroundColor Green
        $ocrText = $best.txtClean
        Copy-Item $best.tsv ($outBase + ".tsv") -Force
        $confAvg = $best.confUsed
        $confAvgAll = $best.confAll
        $chosenLang = $best.lang
        $chosenPsm = $best.psm
      }
      else {
        # --- Final attempts on ORIGINAL image ---
        $finalBest = $best

        foreach ($psm in @(11, 6)) {
          $tryBase2 = Join-Path $OcrTmpDir ($basename + ".try_orig_psm" + $psm)
          Run-Tess -Image $img.FullName -OutBase $tryBase2 -Lang $LangPrimary -Psm $psm -Oem $TessOEM
          Run-Tess -Image $img.FullName -OutBase $tryBase2 -Lang $LangPrimary -Psm $psm -Tsv -Oem $TessOEM

          $tTxt2 = "$tryBase2.txt"; $tTsv2 = "$tryBase2.tsv"
          $hasFinal2 = Test-TextAndTsv -Txt $tTxt2 -Tsv $tTsv2
          if (-not $hasFinal2) { continue }

          $tText2 = Get-Content -LiteralPath $tTxt2 -Raw -Encoding UTF8
          $tBlocksAll2 = @( Parse-Tsv -TsvPath $tTsv2 )
          $tWords2 = @($tBlocksAll2 | Where-Object { $_.level -eq 'word' })
          $tConfAll2 = if ($tWords2.Count) { [int]([Math]::Round((($tWords2 | Measure-Object conf -Average).Average))) } else { 0 }
          $tUsed2 = @($tWords2 | Where-Object { $_.conf -ge $MinConfForBlocks })
          if ($tUsed2.Count -gt $MaxBlocksToKeep) { $tUsed2 = @($tUsed2 | Select-Object -First $MaxBlocksToKeep) }
          $tConfUsed2 = if ($tUsed2.Count) { [int]([Math]::Round((($tUsed2 | Measure-Object conf -Average).Average))) } else { 0 }

          $tClean2 = Convert-TsvToCleanOcrText -TsvPath $tTsv2 -MinConf $MinConfForBlocks
          if ([string]::IsNullOrWhiteSpace($tClean2)) { $tClean2 = $tText2 }

          $isBetter2 = ($tConfUsed2 -gt $finalBest.confUsed) -or (($tConfUsed2 -eq $finalBest.confUsed) -and ($tConfAll2 -gt $finalBest.confAll))
          if ($isBetter2) {
            $finalBest = [pscustomobject]@{
              confUsed = $tConfUsed2
              confAll  = $tConfAll2
              lang     = $LangPrimary
              psm      = $psm
              txt      = $tText2
              txtClean = $tClean2
              tsv      = $tTsv2
            }
          }
        }

        # Final B: psm=12 + deu+eng
        $tryBase3 = Join-Path $OcrTmpDir ($basename + ".try_final_psm12_mix")
        Run-Tess -Image $img.FullName -OutBase $tryBase3 -Lang $LangMixed -Psm 12 -Oem $TessOEM
        Run-Tess -Image $img.FullName -OutBase $tryBase3 -Lang $LangMixed -Psm 12 -Tsv -Oem $TessOEM

        $tTxt3 = "$tryBase3.txt"; $tTsv3 = "$tryBase3.tsv"
        $hasFinal3 = Test-TextAndTsv -Txt $tTxt3 -Tsv $tTsv3
        if ($hasFinal3) {
          $tText3 = Get-Content -LiteralPath $tTxt3 -Raw -Encoding UTF8
          $tBlocksAll3 = @( Parse-Tsv -TsvPath $tTsv3 )
          $tWords3 = @($tBlocksAll3 | Where-Object { $_.level -eq 'word' })
          $tConfAll3 = if ($tWords3.Count) { [int]([Math]::Round((($tWords3 | Measure-Object conf -Average).Average))) } else { 0 }
          $tUsed3 = @($tWords3 | Where-Object { $_.conf -ge $MinConfForBlocks })
          if ($tUsed3.Count -gt $MaxBlocksToKeep) { $tUsed3 = @($tUsed3 | Select-Object -First $MaxBlocksToKeep) }
          $tConfUsed3 = if ($tUsed3.Count) { [int]([Math]::Round((($tUsed3 | Measure-Object conf -Average).Average))) } else { 0 }

          $tClean3 = Convert-TsvToCleanOcrText -TsvPath $tTsv3 -MinConf $MinConfForBlocks
          if ([string]::IsNullOrWhiteSpace($tClean3)) { $tClean3 = $tText3 }

          $isBetter3 = ($tConfUsed3 -gt $finalBest.confUsed) -or (($tConfUsed3 -eq $finalBest.confUsed) -and ($tConfAll3 -gt $finalBest.confAll))
          if ($isBetter3) {
            $finalBest = [pscustomobject]@{
              confUsed = $tConfUsed3
              confAll  = $tConfAll3
              lang     = $LangMixed
              psm      = 12
              txt      = $tText3
              txtClean = $tClean3
              tsv      = $tTsv3
            }
          }
        }

        if ( ($finalBest.confUsed -gt $best.confUsed) -or (($finalBest.confUsed -eq $best.confUsed) -and ($finalBest.confAll -gt $best.confAll)) ) {
          Write-Host ("  Final chosen: lang={0}, psm={1}, conf_used={2}, conf_all={3}" -f $finalBest.lang, $finalBest.psm, $finalBest.confUsed, $finalBest.confAll) -ForegroundColor Green
          $ocrText = $finalBest.txtClean
          Copy-Item $finalBest.tsv ($outBase + ".tsv") -Force
          $confAvg = $finalBest.confUsed
          $confAvgAll = $finalBest.confAll
          $chosenLang = $finalBest.lang
          $chosenPsm = $finalBest.psm
        }
        else {
          Write-Host "  Fallback did not improve." -ForegroundColor DarkYellow
        }
      }
    }


    # Nach evtl. Fallbacks: Clean-Text aus *aktueller* TSV neu generieren (Konsistenz)
    $ocrTextClean = Convert-TsvToCleanOcrText -TsvPath ($outBase + ".tsv") -MinConf $MinConfForBlocks
    if ([string]::IsNullOrWhiteSpace($ocrTextClean)) {
      # Falls TSV leer/kaputt → notfalls auf aktuell gewählten $ocrText zurückfallen
      $ocrTextClean = $ocrText
    }

    # Vision
    $mdPath = Join-Path $CaptionsDir ($basename + ".md")
    $fm = Read-VisionFrontmatter -MarkdownPath $mdPath
    $vision = Extract-VisionSummary -MarkdownPath $mdPath
    if ($fm -eq $null) { Write-Host "  No frontmatter found (ok)" -ForegroundColor DarkGray }

    # Meta
    Write-Host "  Reading image metadata..." -ForegroundColor DarkGray
    $size = Get-ImageSize -Path $img.FullName
    $hash = Get-FileSha1 -Path $img.FullName
    Write-Host ("  Meta: {0}x{1}, {2}" -f $size.width, $size.height, $hash) -ForegroundColor DarkGray

    # Variablen
    $imageVar = if ($fm -and $fm.image) { $fm.image } else { $img.Name }
    $moduleVar = if ($fm) { $fm.module } else { $null }
    $screenVar = if ($fm) { $fm.screen } else { $null }
    $viewVar = if ($fm) { $fm.view } else { $null }
    $capturedVar = if ($fm) { $fm.captured_at } else { $null }
    $sourceVar = if ($fm -and $fm.source_file) { $fm.source_file } else { $img.Name }
    $summaryVar = $vision.summary
    $uiElemsVar = $vision.ui_elements
    $tagsVar = if ($fm) { $fm.tags } else { @() }

    # Markdown säubern
    $summaryVar = Strip-Markdown $summaryVar
    if ($uiElemsVar) { $uiElemsVar = $uiElemsVar | ForEach-Object { Strip-Markdown $_ } }

    # JSON
    $jsonPath = Join-Path $CaptionsDir ($basename + ".json")
    Write-SidecarJsonManual -Path $jsonPath `
      -Image $imageVar -Module $moduleVar -Screen $screenVar -View $viewVar `
      -CapturedAt $capturedVar -SourceFile $sourceVar `
      -Lang $chosenLang -Oem $TessOEM -Psm $chosenPsm -OcrText $ocrTextRaw -ConfAvg $confAvg -ConfAvgAll $confAvgAll `
      -Summary $summaryVar -UiElements $uiElemsVar -Tags $tagsVar `
      -Hash $hash -Width $size.width -Height $size.height

    # RAG
    $ragPath = Join-Path $CaptionsDir ($basename + ".rag.txt")
    $rag = @()
    $rag += "image: $imageVar"
    if ($moduleVar) { $rag += "module: $moduleVar" }
    if ($screenVar) { $rag += "screen: $screenVar" }
    if ($viewVar) { $rag += "view: $viewVar" }
    if ($capturedVar) { $rag += "captured_at: $capturedVar" }
    $rag += "hash: $hash"
    $rag += "size: $($size.width)x$($size.height)"
    if ($summaryVar) { $rag += ""; $rag += "SUMMARY:"; $rag += $summaryVar }
    if ($uiElemsVar -and $uiElemsVar.Count -gt 0) {
      $rag += ""; $rag += "UI_ELEMENTS:"; $rag += ("- " + ($uiElemsVar -join "`r`n- "))
    }

    # (Feinschliff: Zeilen mit nur 1–2 Zeichen entfernen, Mehrfachspaces glätten)
    $ragOcrLines = ($ocrTextClean -split "`r?`n") |
    Where-Object { ($_ -match '\S') -and ($_.Trim().Length -gt 2) }
    $ragOcrLines = $ragOcrLines -replace '\s{2,}', ' '
    $ragOcrText = ($ragOcrLines -join "`n").Trim()

    $rag += ""
    $rag += ("OCR (lang={0}, oem={1}, psm={2}, conf_avg={3}, conf_avg_all={4}):" -f `
        $chosenLang, $TessOEM, $chosenPsm, [int][math]::Round($confAvg), [int][math]::Round($confAvgAll))
    $rag += $ragOcrText
    [System.IO.File]::WriteAllLines($ragPath, $rag, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  RAG flat written -> {0}" -f $ragPath) -ForegroundColor DarkGray

    # norm.txt (aus bereinigtem Text)
    $normPath = Join-Path $CaptionsDir ($basename + ".norm.txt")
    $normBase = @()
    if ($summaryVar) { $normBase += $summaryVar }
    if ($uiElemsVar -and $uiElemsVar.Count) { $normBase += ($uiElemsVar -join " ") }
    $normBase += $ocrTextClean
    $normText = ($normBase -join " ").ToLower()
    $normText = $normText -replace "ä", "ae" -replace "ö", "oe" -replace "ü", "ue" -replace "ß", "ss"
    $normText = $normText -replace "[^\w\s€%.,:+/-]", " "
    $normText = $normText -replace "\s+", " "
    [System.IO.File]::WriteAllText($normPath, $normText, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host ("[OK] {0}/{1}  {2}  ->  {3}" -f $idx, $tot, $img.Name, $jsonPath) -ForegroundColor Green
  }
  catch {
    Write-Host ("[ERROR] {0}/{1}  {2}: {3}" -f $idx, $tot, $img.Name, $_.Exception.Message) -ForegroundColor Red
    continue
  }
}
