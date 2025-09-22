param(
  [Parameter(Mandatory=$false)]
  [string[]] $Roots = @("."),  # Startordner
  [string[]] $Extensions = @("css","scss","sql","ttf","svg","gz","png","jpg","jpeg","gif","log","bak","tmp","temp","old","swp","swo"), # Zu löschende Dateiendungen
  [switch] $DryRun,            # Vorschau: nichts wird gelöscht
  [switch] $Force,             # Force an Remove-Item
  [switch] $Recycle,           # Statt hart löschen in den Papierkorb verschieben
  [string[]] $ExcludePaths = @("node_modules","vendor",".git",".idea",".vscode") # Ordner-Ausschlüsse (Teilstrings)
)

# --- Hilfsfunktionen ---
function Normalize-Ext([string[]]$exts){
  return $exts | ForEach-Object {
    $_ = $_.Trim()
    if ($_ -notlike ".*") { ".$_" } else { $_ }
  }
}

function Should-Exclude([string]$path, [string[]]$excludes){
  foreach($ex in $excludes){
    if ($path -like "*\$ex\*" -or $path -like "*$ex/*") { return $true }
  }
  return $false
}

$normalizedExts = Normalize-Ext $Extensions
$allFiles = @()

foreach($root in $Roots){
  if (-not (Test-Path $root)) {
    Write-Warning "Root nicht gefunden: $root"
    continue
  }

  # Schneller Filter per -Include funktioniert zuverlässig, wenn -Path ein Ordner mit Wildcard ist.
  # Daher nutzen wir globbing: "$root\**\*" (PowerShell 7+) oder filtern nachträglich.
  $files = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue
  $files = $files | Where-Object {
    $normalizedExts -contains $_.Extension.ToLower() -and
    -not (Should-Exclude $_.FullName $ExcludePaths)
  }

  $allFiles += $files
}

if (-not $allFiles) {
  Write-Host "Keine passenden Dateien gefunden." -ForegroundColor Yellow
  return
}

# Zusammenfassung anzeigen
$group = $allFiles | Group-Object Extension | Sort-Object Name
Write-Host "Treffer:" -ForegroundColor Cyan
$group | ForEach-Object {
  $count = $_.Count
  $mb = "{0:N1}" -f ( ($_.Group | Measure-Object Length -Sum).Sum / 1MB )
  Write-Host ("{0,-8}  {1,6}  {2,6} MB" -f $_.Name, $count, $mb)
}

if ($DryRun){
  Write-Host "`nDry-Run aktiv: Es werden KEINE Dateien gelöscht." -ForegroundColor Yellow
  return
}

if ($Recycle){
  # Papierkorb-Variante via .NET (Microsoft.VisualBasic)
  Add-Type -AssemblyName Microsoft.VisualBasic
  $deleted = 0
  foreach($f in $allFiles){
    try {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
        $f.FullName,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
      )
      $deleted++
    } catch {
      Write-Warning "Konnte nicht in den Papierkorb verschieben: $($f.FullName) - $($_.Exception.Message)"
    }
  }
  Write-Host "`nIn den Papierkorb verschoben: $deleted Dateien." -ForegroundColor Green
} else {
  # Hart löschen
  $params = @{ ErrorAction = 'SilentlyContinue' }
  if ($Force) { $params.Force = $true }
  $allFiles | Remove-Item @params
  Write-Host "`nGelöscht: $($allFiles.Count) Dateien." -ForegroundColor Green
}
