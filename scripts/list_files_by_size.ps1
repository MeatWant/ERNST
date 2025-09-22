
# PowerShell: Dateitypen im Projektverzeichnis nach Größe sortieren

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $Root = "D:\dein\repo"
)

Get-ChildItem $Root -Recurse -File |
  Group-Object Extension | Sort-Object Count -Descending |
  Select-Object @{n="Ext";e={$_.Name}}, Count, @{n="MB";e={[math]::Round(($_.Group | Measure-Object Length -Sum).Sum/1MB,1)}}