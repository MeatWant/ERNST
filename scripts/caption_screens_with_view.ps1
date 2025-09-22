<#
.SYNOPSIS
  Caption-Markdown für UI-Screenshots mit Ollama Vision.
#>
param(
  [string]$DocsRoot = "D:\KI\OpenWebUI\docs\screenshots",
  [string]$Model = "llava:13b",
  [string]$OllamaUrl = "http://127.0.0.1:11434",
  [switch]$UseFoldersAsModuleScreen,
  [switch]$Force,
  [int]$MaxRetries = 2,
  [string]$TimezoneOffset = "+02:00",
  [switch]$SanitizeAscii,

  # Neue Parameter für Sampling
  [double]$Temperature = 0.2,
  [double]$TopP = 0.8,
  [double]$RepeatPenalty = 1.1,
  [int]$NumCtx = 8192,
  [int]$NumPredict = 1024,
  [int]$GpuLayers = 999,   # 999 = so viel wie möglich auf die GPU
  [int]$NumThread = 0,      # 0 = Auto; optional zum CPU-Tuning

  [switch]$Timing,

  # Bildverarbeitung
  [int]$MaxImageWidth = 1600,
  [int]$JpegQuality   = 85,
  [switch]$Downscale

)


$ErrorActionPreference = "Stop"

# ==========================
# Encoding + Pipeline-Setup
# ==========================
$Utf8NoBom   = [System.Text.UTF8Encoding]::new($false)

[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding           = $Utf8NoBom
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Get-Content:Encoding'] = 'utf8'
try { chcp 65001 | Out-Null; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# Pfade
$rawDir = Join-Path $DocsRoot "raw"
$outDir = Join-Path $DocsRoot "captions"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# ============
# Hilfsfunktionen
# ============

#region --- UTF-8 & Emoji-Helpers ---

# Konsole/Skript auf UTF-8 trimmen (harmlos, auch wenn schon UTF-8 aktiv ist)
function Initialize-UTF8 {
  try {
    if ($IsWindows) { chcp 65001 > $null 2>&1 }
  } catch {}
  [Console]::InputEncoding  = [Text.UTF8Encoding]::new()
  [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
}
Initialize-UTF8

# "U+1F37E", "1F37E", "23F1", "u{1F468}" -> tatsächliches Zeichen (🍾, ⏱, 👨, …)
function Convert-UCodepointToString {
  param([Parameter(Mandatory)][string]$CodePoint)

  # normalisieren
  $cp = $CodePoint.Trim()
  $cp = $cp -replace '^(?i)U\+','' -replace '^(?i)u\{','' -replace '\}$',''
  # hex -> int
  $value = [int]::Parse($cp, [Globalization.NumberStyles]::HexNumber)

  # universell: .NET bildet auch Surrogatpaare (für > U+FFFF)
  return [char]::ConvertFromUtf32($value)
}

# Häufige Status-Icons als Hashtable
$Emoji = @{
  "done"     = "1F37E"  # 🍾 Sektkorken - Fertig/Erfolg
  "ok"       = "2705"   # ✅ Erledigt
  "warn"     = "26A0"   # ⚠️  Warnung
  "error"    = "274C"   # ❌ Fehler
  "info"     = "2139"   # ℹ️  Info
  "time"     = "23F1"   # ⏱ Stoppuhr
  "rocket"   = "1F680"  # 🚀 Start
  "man"      = "1F468"  # 👨 Benutzer
  "woman"    = "1F469"  # 👩 Benutzerin
  "gear"     = "2699"   # ⚙️  Einstellungen
  "work"     = "1F6E0"  # 🛠️  <- neu: am Arbeiten
}

# Komfort: Emoji + Nachricht ausgeben (funktioniert in PS 5.1 und 7+)
function Write-Emoji {
  param(
    [Parameter(Mandatory)][string]$CodePoint,
    [Parameter(Mandatory)][string]$Message,
    [ConsoleColor]$ForegroundColor = "White",
    [ConsoleColor]$BackgroundColor
  )

  $emoji = Convert-UCodepointToString $CodePoint
  $text  = "$emoji  $Message"

  if ($PSBoundParameters.ContainsKey('BackgroundColor')) {
    Write-Host $text -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
  } else {
    Write-Host $text -ForegroundColor $ForegroundColor
  }
}



#endregion



function Get-ImageBase64([string]$path) {
  if (-not $Downscale) {
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
  }
  Add-Type -AssemblyName System.Drawing
  $img = [System.Drawing.Image]::FromFile($path)
  try {
    if ($img.Width -le $MaxImageWidth) {
      $ms = New-Object IO.MemoryStream
      $img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
      $bytes = $ms.ToArray()
      $ms.Dispose()
      return [Convert]::ToBase64String($bytes)
    } else {
      $newW = $MaxImageWidth
      $newH = [int][math]::Round($img.Height * ($newW / $img.Width))
      $bmp = New-Object System.Drawing.Bitmap($newW, $newH)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.CompositingQuality = 'HighQuality'
      $g.SmoothingMode      = 'HighQuality'
      $g.InterpolationMode  = 'HighQualityBicubic'
      $g.DrawImage($img, 0, 0, $newW, $newH)
      $g.Dispose()

      # JPEG-Encoder mit Qualität
      $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | ? { $_.MimeType -eq 'image/jpeg' }
      $ep  = New-Object System.Drawing.Imaging.EncoderParameters(1)
      $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$JpegQuality)
      $ms = New-Object IO.MemoryStream
      $bmp.Save($ms, $enc, $ep)
      $bytes = $ms.ToArray()
      $ms.Dispose()
      $bmp.Dispose()

      return [Convert]::ToBase64String($bytes)
    }
  } finally {
    $img.Dispose()
  }
}


# z. B. 20250913_Module_Screen_View_mit_unterstrichen(_v2)?.png
$fnameRegex = '^(?<date>\d{8})_(?<module>[^_]+)_(?<screen>[^_]+)_(?<view>[^.]+?)(?:_v(?<ver>\d+))?\.(png|jpg|jpeg)$'

function Derive-MSV([System.IO.FileInfo]$file) {
  if ($UseFoldersAsModuleScreen) {
    $rel = $file.FullName.Substring($rawDir.Length).TrimStart([char]'\', [char]'/')
    $parts = $rel.Split([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $module=$null;$screen=$null;$view=$null
    if ($parts.Length -ge 2) { $module=$parts[0]; $screen=$parts[1] }
    if ($parts.Length -ge 3) {
      if (Test-Path (Join-Path $rawDir (Join-Path $parts[0] (Join-Path $parts[1] $parts[2])))) {
        $view=$parts[2]
      }
    }
    if (-not $view) {
      $bn = $file.BaseName
      $m2 = [regex]::Match($bn, '_(?<view>[^_]+)$')
      if ($m2.Success) { $view = $m2.Groups['view'].Value }
    }
    return @{ module=$module; screen=$screen; view=$view }
  } else {
    $m = [regex]::Match($file.Name, $fnameRegex, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
      return @{
        date   = $m.Groups['date'].Value
        module = $m.Groups['module'].Value
        screen = $m.Groups['screen'].Value
        view   = $m.Groups['view'].Value
        ver    = $m.Groups['ver'].Value
      }
    } else {
      $parts = $file.BaseName -split '_'
      $module=$null;$screen=$null;$view=$null
      if ($parts.Length -ge 3) { $module=$parts[0]; $screen=$parts[1]; $view=$parts[2] }
      elseif ($parts.Length -ge 2) { $module=$parts[0]; $screen=$parts[1] }
      else { $screen = $file.BaseName }
      return @{ module=$module; screen=$screen; view=$view }
    }
  }
}

function Escape-Yaml([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return "" }
  $s = $s -replace '\\', '\\\\'
  $s = $s -replace '"','\"'
  return '"' + $s + '"'
}

function To-Tags([string[]]$parts) {
  $clean = @()
  foreach ($p in $parts) {
    if ($null -eq $p) { continue }
    foreach ($tok in ($p -split '[_\-]')) {
      $t = $tok.Trim().ToLowerInvariant()
      if ($t.Length -gt 0) { $clean += $t }
    }
  }
  $seen=@{}; $uniq=@()
  foreach ($c in $clean) { if (-not $seen.ContainsKey($c)) { $seen[$c]=$true; $uniq+=$c } }
  return $uniq
}

# -------- Prompt (EN) → Output in German (ohne Here-String) V1 Prompt --------
$instruction =  @(
'You are a technical writer. You have a deep understanding of the subject matter. Especially the context writing User Documentation for Applications. Carefully analyze the screenshot and provide a concise but detailed description in GERMAN language.',
'Context:',
'- Module: {{MODULE}}',
'- Screen: {{SCREEN}}',
'- View: {{VIEW}}',
'Instructions:',
'1. Begin with a short 1–3 sentence summary describing the purpose of this view.',
'2. Use only what is clearly visible in the image. No assumptions.',
'3. List all clearly visible UI elements such as tables, buttons, input fields, labels, or messages. For each element, mention its function. If a list or table is present, summarize the shown header.',
'4. Only list a maximum of 5 rows in a table. If there are more, summarize the rest as "and X more elements".',
'5. Provide a brief description of each UI element and its purpose. Avoid redundancy.',
'6. Provide a step-by-step description of how a user would typically use this view.',
'7. Add notes if there are warnings, error messages, totals, prices, or other important information.',
'Important:',
'- Use only what is actually visible in the screenshot.',
'- Output must be in GERMAN.',
'- Do not invent features. If something is unclear, omit it.',
'- Use plain Markdown formatting as follows:',
'','# {Modul} – {Screen} – {View}',
'','**Zweck:** <summary in German>',
'','## Sichtbare UI-Elemente',
'- <Element – Funktion>',
'- <Element – Funktion>',
'','## Schritt-für-Schritt',
'1. <Aktion>',
'2. <Aktion>',
'3. <optional weitere Aktion>',
'','## Hinweise',
'- <Hinweis, Fehlermeldung, Berechtigung>'
) -join "`r`n"

# ------------------------------------------------

# --- Unicode-Normalisierung & (optional) ASCII-Transliteration ---
function Normalize-Unicode([string]$s) {
  if (-not $s) { return $s }
  return $s.Normalize([Text.NormalizationForm]::FormC)
}

function Sanitize-Text([string]$s, [bool]$toAscii=$false) {
  if (-not $s) { return $s }

  # Unsichtbare/Problemchars
  $s = $s -replace '[\u00AD\u200B\u200C\u200D\u2060]', ''   # Soft hyphen, zero-width
  $s = $s -replace '\u00A0', ' '                            # nbsp → space
  # Typografik zu ASCII
  $s = $s -replace '[\u2018\u2019\u2032]', "'"              # ‘ ’ ′
  $s = $s -replace '[\u201C\u201D\u2033]', '"'              # “ ”
  $s = $s -replace '[\u2013\u2014]', '-'                    # – —
  $s = $s -replace '\u2026', '...'                          # …
  $s = $s -replace '[\u2212]', '-'                          # −

  if ($toAscii) {
    $map = @{
      'ä'='ae'; 'ö'='oe'; 'ü'='ue'; 'ß'='ss';
      'Ä'='Ae'; 'Ö'='Oe'; 'Ü'='Ue'
    }
    $s = ($s.ToCharArray() | ForEach-Object {
      $ch = $_.ToString()
      if ($map.ContainsKey($ch)) { $map[$ch] } else { $ch }
    }) -join ''
    $formD = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $formD.ToCharArray()) {
      if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne 'NonSpacingMark') {
        [void]$sb.Append($c)
      }
    }
    $s = $sb.ToString()
  }

  return Normalize-Unicode $s
}

function Repair-Mojibake {
  param([string]$s)
  if (-not $s) { return $s }

  $needsFix = {
    param($t)
    return ($t -match "\u00C3[\u0080-\u00BF]") -or ($t -match "\u00E2[\u0080-\u00BF]{2}")
  }

  $prev = $s
  for ($i = 0; $i -lt 2; $i++) {
    if (-not (& $needsFix $s)) { break }
    try {
      $bytes = [Text.Encoding]::GetEncoding(1252).GetBytes($s)
      $s = [Text.Encoding]::UTF8.GetString($bytes)
      if ($s -eq $prev) { break }
      $prev = $s
    } catch {
      break
    }
  }
  return $s
}

# -------------------------------------------------------------------

function Call-Ollama([string]$b64, [string]$prompt, [int]$retries=2) {
# Optionen zuerst ohne bedingte Felder bauen
$options = @{
  temperature    = $Temperature
  top_p          = $TopP
  repeat_penalty = $RepeatPenalty
  num_ctx        = $NumCtx
  num_predict    = $NumPredict
}

# Optional: GPU-Offload setzen (beide Keys für maximale Kompatibilität)
if ($GpuLayers -gt 0) {
  $options.gpu_layers     = $GpuLayers
  $options.num_gpu_layers = $GpuLayers
}

# Optional: CPU-Threads setzen (nur wenn >0)
if ($NumThread -gt 0) {
  $options.num_thread = $NumThread
}

$payload = @{
  model    = $Model
  messages = @(@{ role="user"; content=$prompt; images=@($b64) })
  stream   = $false
  options  = $options
}
$json = $payload | ConvertTo-Json -Depth 10 -Compress


  $attempt  = 0
  $totalSw  = [System.Diagnostics.Stopwatch]::StartNew()

  do {
    $attempt++
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

      $resp = Invoke-WebRequest -Method Post `
        -Uri "$OllamaUrl/api/chat" `
        -ContentType "application/json; charset=utf-8" `
        -Headers @{ "Accept"="application/json"; "Accept-Charset"="utf-8" } `
        -Body $bytes `
        -TimeoutSec 600

      $ms = New-Object System.IO.MemoryStream
      $resp.RawContentStream.CopyTo($ms)
      $rawBytes = $ms.ToArray()
      $ms.Dispose()

      $text = [System.Text.Encoding]::UTF8.GetString($rawBytes)

      $sw.Stop()
      if ($Timing) {
        # Write-Emoji $Emoji['time'] ("[API] attempt {0}: {1:N2}s" -f $attempt, $sw.Elapsed.TotalSeconds) -ForegroundColor Cyan
        # Write-Host ("[API] attempt {0}: {1:N2}s" -f $attempt, $sw.Elapsed.TotalSeconds) -ForegroundColor Cyan
      }

      $obj = $text | ConvertFrom-Json -ErrorAction Stop

      if ($Timing) {
        $pred = $obj.eval_count
        $pp   = $obj.prompt_eval_count
        if ($pred -or $pp) {
          Write-Emoji $Emoji['gear'] ("[TOKENS] prompt={0} predict={1}" -f $pp, $pred) -ForegroundColor DarkCyan
        }
      }

      $totalSw.Stop()
      # Zeiten ans Objekt hängen (stört deine jetzige Nutzung nicht)
      $obj | Add-Member -NotePropertyName request_ms -NotePropertyValue ([math]::Round($sw.Elapsed.TotalMilliseconds,1)) -Force
      $obj | Add-Member -NotePropertyName total_ms   -NotePropertyValue ([math]::Round($totalSw.Elapsed.TotalMilliseconds,1)) -Force

      return $obj

    } catch {
      $sw.Stop()
      if ($Timing) {
        Write-Warning ("[API] failed attempt {0} after {1:N2}s: {2}" -f $attempt, $sw.Elapsed.TotalSeconds, $_.Exception.Message)
      }
      if ($attempt -ge $retries) { throw }
      Start-Sleep -Seconds ([Math]::Min(2*$attempt, 5))
    }
  } while ($true)
}


# ---------------------------------------------------

Write-Emoji $Emoji['rocket'] "Starte Verarbeitung..."

$images = Get-ChildItem -Path $rawDir -File -Include *.png,*.jpg,*.jpeg -Recurse | Sort-Object FullName
if (-not $images) { Write-Warning "Keine Bilder in $rawDir gefunden."; return }

$indexRows = @()

foreach ($imgFile in $images) {
  $imgSw = [System.Diagnostics.Stopwatch]::StartNew()

  $img = $imgFile.FullName
  $base = $imgFile.BaseName
  $mdPath = Join-Path $outDir ($base + ".md")

  if (-not $Force -and (Test-Path $mdPath) -and ((Get-Item $mdPath).LastWriteTimeUtc -ge (Get-Item $img).LastWriteTimeUtc)) {
    # Write-Host ">> Überspringe (aktuell): $($imgFile.Name)"
    Write-Output ([System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes("⏭️ Überspringe (aktuell): $($imgFile.Name)")))
    $msv = Derive-MSV $imgFile
    $indexRows += [PSCustomObject]@{ Img=$imgFile.Name; Module=$msv.module; Screen=$msv.screen; View=$msv.view; Md=("./captions/" + $base + ".md") }
    continue
  }

  $ms = Derive-MSV $imgFile
  $module = if ($ms.module) { $ms.module } else { "unknown" }
  $screen = if ($ms.screen) { $ms.screen } else { $base }
  $view   = if ($ms.view)   { $ms.view }   else { "" }

  $module = Normalize-Unicode $module
  $screen = Normalize-Unicode $screen
  $view   = Normalize-Unicode $view

  $prompt = $instruction.Replace("{{MODULE}}",$module).Replace("{{SCREEN}}",$screen).Replace("{{VIEW}}",$view)

  $tags = To-Tags @($module,$screen,$view)
  $tagsYaml = if ($tags.Count -gt 0) { "[" + ( ($tags | ForEach-Object { '"' + $_ + '"' }) -join ", " ) + "]" } else { "[]" }

  Write-Emoji $Emoji['work'] ("[IMG] Verarbeite $($imgFile.Name)") -ForegroundColor Yellow
  # Write-Host "`n [IMG] Verarbeite $($imgFile.Name)" -ForegroundColor Yellow

  $b64 = Get-ImageBase64 $img
  $resp = Call-Ollama -b64 $b64 -prompt $prompt -retries $MaxRetries

  $md = if ($resp.message -and $resp.message.content) { $resp.message.content } else { $resp.response }

  $md = Repair-Mojibake $md
  $md = Sanitize-Text $md $SanitizeAscii.IsPresent

  $headerSep = ' - '
  $header = "# $module$headerSep$screen" + ($(if ($view) { "$headerSep$view" } else { "" }))
  if ($md -notmatch '^\s*#\s+') { $md = $header + "`r`n`r`n" + $md }

  $imgRel = "../raw/$($imgFile.FullName.Substring($rawDir.Length).TrimStart([char]'\', [char]'/'))"
  $capturedAt = (Get-Date).ToString("s") + $TimezoneOffset

  $frontmatter = @(
    '---',
    "type: screenshot",
    "image: $imgRel",
    "module: $(Escape-Yaml $module)",
    "screen: $(Escape-Yaml $screen)",
    "view: $(Escape-Yaml $view)",
    "tags: $tagsYaml",
    "captured_at: $capturedAt",
    "source_file: ""$($imgFile.Name)""",
    '---'
  ) -join "`r`n"

  $final = $frontmatter + "`r`n`r`n" + $md + "`r`n`r`n" + "![Screenshot]($imgRel)" + "`r`n"

  [System.IO.File]::WriteAllText($mdPath, $final, $Utf8NoBom)
  $imgSw.Stop()
  if ($Timing) {
    Write-Emoji $Emoji['time'] ("[IMG] {0} - {1:N2}s total" -f $imgFile.Name, $imgSw.Elapsed.TotalSeconds) -ForegroundColor Green
    # Write-Host ("[IMG] {0} - {1:N2}s total" -f $imgFile.Name, $imgSw.Elapsed.TotalSeconds) -ForegroundColor Green
  }

  $indexRows += [PSCustomObject]@{ Img=$imgFile.Name; Module=$module; Screen=$screen; View=$view; Md=("./captions/" + $base + ".md") }
}

# Index schreiben (UTF-8 ohne BOM)
$indexPath = Join-Path $DocsRoot "_index.md"
$lines = @(
  "# Screenshots - Übersicht",
  "",
  "| Bild | Modul | Screen | View | Beschreibung |",
  "|---|---|---|---|---|"
)
foreach ($r in $indexRows | Sort-Object Module, Screen, View, Img) {
  $imgRel = "./raw/" + $r.Img
  $name   = [IO.Path]::GetFileNameWithoutExtension($r.Img)
  $mdRel  = $r.Md
  $lines += ("| ![]({0}) | {1} | {2} | {3} | [{4}]({5}) |" -f $imgRel, $r.Module, $r.Screen, $r.View, $name, $mdRel)
}
[System.IO.File]::WriteAllText($indexPath, ($lines -join "`r`n"), $Utf8NoBom)

Write-Emoji $Emoji['ok'] "Fertig. Markdown-Sidecars unter: $outDir" -ForegroundColor Green
# Write-Host "Fertig. Markdown-Sidecars unter: $outDir"

Write-Host "Index: $indexPath"
