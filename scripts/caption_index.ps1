$captionsDir = "D:\KI\OpenWebUI\docs\screenshots\captions"
$indexPath   = Join-Path (Split-Path $captionsDir -Parent) "_index.md"

$lines = @("# Screenshots – Übersicht", "", "| Bild | Titel/Seite |", "|---|---|")
Get-ChildItem $captionsDir -File -Filter *.md | ForEach-Object {
  $name = $_.BaseName
  $imgRel = "./raw/$name.png"
  $mdRel  = "./captions/$name.md"
  $lines += @("| ![]($imgRel) | [$name]($mdRel) |")
}
Set-Content -Path $indexPath -Value ($lines -join "`r`n") -Encoding UTF8
