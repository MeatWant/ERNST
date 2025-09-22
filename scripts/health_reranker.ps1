param(
  [string]$WebUiUrl = "http://localhost:3000",
  [string]$ExpectedModel = "BAAI/bge-reranker-v2-m3"
)

function Get-OwuiStatus {
  try {
    return Invoke-RestMethod -Uri "$WebUiUrl/api/status" -Method GET -TimeoutSec 5
  } catch {
    return $null
  }
}

Write-Host ("==> Prüfe Open WebUI unter {0}" -f $WebUiUrl) -ForegroundColor Cyan

# 1) Versuche eine Status-API (wenn vorhanden)
$status = Get-OwuiStatus
if ($status) {
  $asJson = $status | ConvertTo-Json -Depth 6
  if ($asJson -match [Regex]::Escape($ExpectedModel)) {
    Write-Host ("OK: Reranker '{0}' erscheint in /api/status." -f $ExpectedModel) -ForegroundColor Green
    exit 0
  } else {
    Write-Host ("Hinweis: '{0}' nicht in /api/status gefunden. Prüfe Logs als Nächstes..." -f $ExpectedModel) -ForegroundColor DarkYellow
  }
} else {
  Write-Host "Hinweis: /api/status nicht verfügbar. Prüfe Logs als Nächstes..." -ForegroundColor DarkYellow
}

# 2) Fallback: Simple Log-/Ping-Check über eine harmlose Anfrage
try {
  $pingBody = @{ query = "ping"; top_k = 1; rerank = $true } | ConvertTo-Json
  # wir triggern eine Mini-Suche, damit OWUI (falls noch nicht) den Reranker lädt
  $null = Invoke-RestMethod -Uri "$WebUiUrl/api/retrieval/query" -Method POST -Body $pingBody -ContentType "application/json"
} catch { }

# 3) Letzter Fallback: Direkt im Dateisystem nachsehen (nur wenn OWUI lokal mit gemountetem Cache läuft)
$hfCacheCandidates = @(
  "$env:USERPROFILE\.cache\huggingface",
  "$env:USERPROFILE\AppData\Local\huggingface",
  "C:\Users\Public\.cache\huggingface",
  "/root/.cache/huggingface"
)

$found = $false
foreach ($dir in $hfCacheCandidates) {
  if ([string]::IsNullOrWhiteSpace($dir)) { continue }
  if (Test-Path $dir) {
    $hit = Get-ChildItem -Path $dir -Recurse -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -like "*$ExpectedModel*" } |
           Select-Object -First 1
    if ($hit) {
      Write-Host ("OK: Reranker-Dateien im HF-Cache gefunden: {0}" -f $hit.FullName) -ForegroundColor Green
      $found = $true
      break
    }
  }
}

if (-not $found) {
  Write-Host ("Nicht gefunden: '{0}'. Lade das Modell vorab:" -f $ExpectedModel) -ForegroundColor Red
  Write-Host "  docker exec -it openwebui bash" -ForegroundColor DarkGray
  Write-Host "  pip install -U FlagEmbedding" -ForegroundColor DarkGray
  Write-Host ("  python -c ""from FlagEmbedding import FlagReranker; FlagReranker('{0}')""" -f $ExpectedModel) -ForegroundColor DarkGray
  exit 1
}
