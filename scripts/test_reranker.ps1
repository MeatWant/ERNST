param(
  [string]$WebUiUrl = "http://localhost:3000",
  [string]$Query    = "Finde die Artikelliste im Einkaufsmanagement",
  [string]$Token    = ""  # optional: Bearer-Token, falls OWUI-Auth aktiv ist
)

$headers = @{}
if ($Token -and $Token.Trim().Length -gt 0) { $headers["Authorization"] = "Bearer $Token" }

# Kandidaten-Endpunkte (versch. OWUI-/Fork-Versionen nutzen unterschiedliche Routen)
$targets = @(
  @{ Method="GET";  Url="/api/search";               QueryParam="q"         },
  @{ Method="GET";  Url="/api/rag/search";           QueryParam="q"         },
  @{ Method="GET";  Url="/api/v1/search";            QueryParam="q"         },
  @{ Method="POST"; Url="/api/retrieval/query";      Body=@{query=$Query;top_k=8;rerank=$true} },
  @{ Method="POST"; Url="/api/rag/query";            Body=@{query=$Query;top_k=8;rerank=$true} },
  @{ Method="POST"; Url="/api/v1/rag/query";         Body=@{query=$Query;top_k=8;rerank=$true} }
)

Write-Host ("==> Open WebUI Base: {0}" -f $WebUiUrl) -ForegroundColor Cyan
Write-Host ("==> Query          : {0}" -f $Query)     -ForegroundColor Yellow

$worked = $false
foreach ($t in $targets) {
  $fullUrl = $WebUiUrl.TrimEnd('/') + $t.Url
  try {
    if ($t.Method -eq "GET") {
      $uri = $fullUrl + "?" + ($t.QueryParam + "=" + [System.Web.HttpUtility]::UrlEncode($Query))
      Write-Host ("-- TRY {0} {1}" -f $t.Method, $uri) -ForegroundColor DarkCyan
      $resp = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -TimeoutSec 10
    }
    else {
      $bodyJson = ($t.Body | ConvertTo-Json -Depth 6)
      Write-Host ("-- TRY {0} {1}" -f $t.Method, $fullUrl) -ForegroundColor DarkCyan
      $resp = Invoke-RestMethod -Uri $fullUrl -Method POST -Headers $headers -TimeoutSec 10 `
                                -Body $bodyJson -ContentType "application/json"
    }

    if ($null -eq $resp) { throw "Empty response" }

    # Treffer normalisieren (versch. Schemas)
    $hits = $null
    if ($resp.hits) { $hits = $resp.hits }
    elseif ($resp.results) { $hits = $resp.results }
    elseif ($resp.items) { $hits = $resp.items }

    if ($hits -and $hits.Count -gt 0) {
      Write-Host "`n==> Ergebnisse (nach Retrieval/Rerank falls aktiv):" -ForegroundColor Green
      $i = 0
      foreach ($h in $hits) {
        $i++
        $score  = $h.score
        if (-not $score -and $h.rerank_score) { $score = $h.rerank_score }
        $source = $h.metadata.source_file
        if (-not $source) { $source = $h.metadata.path }
        if (-not $source) { $source = $h.source }
        Write-Host ("{0,2}. Score: {1,-10} | Quelle: {2}" -f $i, $score, $source)
        if ($i -ge 10) { break }
      }
      $worked = $true
      break
    }
    else {
      Write-Host "Hinweis: Endpoint antwortete, aber keine Trefferstruktur erkannt." -ForegroundColor DarkYellow
    }
  }
  catch {
    $status = $_.Exception.Response.StatusCode.Value__
    if ($status) {
      Write-Host ("Fehler {0} bei {1} {2}" -f $status, $t.Method, $fullUrl) -ForegroundColor Red
    } else {
      Write-Host ("Fehler bei {0} {1}: {2}" -f $t.Method, $fullUrl, $_.Exception.Message) -ForegroundColor Red
    }
  }
}

if (-not $worked) {
  Write-Host "Kein kompatibler Endpoint gefunden oder Abfrage fehlgeschlagen." -ForegroundColor Red
  Write-Host "Prüfe ggf. Auth-Token, OWUI-Version oder nutze den Health-Check darunter." -ForegroundColor DarkGray
  exit 2
}
