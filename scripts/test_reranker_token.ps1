param(
  [string]$WebUiUrl = "http://127.0.0.1:3000",
  [string]$Query    = "Finde die Artikelliste im Einkaufsmanagement",
  [Parameter(Mandatory=$true)]
  [string]$Token
)

Add-Type -AssemblyName System.Web

# Beide Header-Varianten probieren
$headersList = @(
  @{ "x-api-key" = $Token; "Accept"="application/json"; "Content-Type"="application/json" },
  @{ "Authorization" = "Bearer $Token"; "Accept"="application/json"; "Content-Type"="application/json" }
)

# Kandidaten-Endpunkte (versch. OWUI-Builds)
$targets = @(
  @{ Method="POST"; Url="/api/v1/rag/query";    Body=@{query=$Query; top_k=8; rerank=$true} },
  @{ Method="GET";  Url="/api/v1/rag/search";   Q="q" },
  @{ Method="GET";  Url="/api/v1/search";       Q="q" },
  @{ Method="POST"; Url="/api/retrieval/query"; Body=@{query=$Query; top_k=8; rerank=$true} },
  @{ Method="POST"; Url="/api/rag/query";       Body=@{query=$Query; top_k=8; rerank=$true} },
  @{ Method="GET";  Url="/api/rag/search";      Q="q" },
  @{ Method="GET";  Url="/api/search";          Q="q" }
)

Write-Host ("==> Base: {0}" -f $WebUiUrl) -ForegroundColor Cyan
Write-Host ("==> Query: {0}" -f $Query)     -ForegroundColor Yellow

function Parse-Hits {
  param($resp)
  if ($null -eq $resp) { return @() }
  $candidates = @($resp.hits, $resp.results, $resp.items, $resp.documents, $resp.data) | Where-Object { $_ }
  foreach ($list in $candidates) {
    if ($list -and $list.data) { $list = $list.data }
    if ($list -and $list.Count -gt 0) { return ,$list }
  }
  return @()
}

$ok = $false

foreach($headers in $headersList){
  Write-Host ("-- Probiere Header: {0}" -f (($headers.Keys -join ", "))) -ForegroundColor DarkGray

  foreach($t in $targets){
    $url = $WebUiUrl.TrimEnd('/') + $t.Url
    try{
      if($t.Method -eq "GET"){
        $uri = $url + "?" + ($t.Q + "=" + [System.Web.HttpUtility]::UrlEncode($Query))
        Write-Host ("-- TRY GET  {0}" -f $uri) -ForegroundColor DarkCyan
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -TimeoutSec 10
      } else {
        $body = ($t.Body | ConvertTo-Json -Depth 8)
        Write-Host ("-- TRY POST {0}" -f $url) -ForegroundColor DarkCyan
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method POST -Body $body -TimeoutSec 15
      }

      # HTML-String => nicht authentifiziert / falscher Pfad
      if ($resp -is [string]) {
        $s = $resp.TrimStart()
        if ($s.StartsWith("<!doctype", "OrdinalIgnoreCase") -or $s.StartsWith("<html", "OrdinalIgnoreCase")) {
          Write-Host "Hinweis: HTML erhalten (vermutlich nicht-authentifiziert oder falscher Pfad). Weiter..." -ForegroundColor DarkYellow
          continue
        }
      }

      $hits = Parse-Hits $resp
      if($hits.Count -gt 0){
        Write-Host "`n==> Ergebnisse:" -ForegroundColor Green
        $i=0
        foreach($h in $hits){
          $i++
          # Score ermitteln
          $score = $null
          if ($h.PSObject.Properties.Name -contains 'score') { $score = $h.score }
          if (-not $score -and $h.PSObject.Properties.Name -contains 'rerank_score') { $score = $h.rerank_score }
          if (-not $score -and $h.PSObject.Properties.Name -contains 'similarity') { $score = $h.similarity }
          if (-not $score -and $h.PSObject.Properties.Name -contains 'rank') { $score = $h.rank }

          # Quelle ermitteln
          $source = $null
          if ($h.PSObject.Properties.Name -contains 'metadata' -and $h.metadata) {
            if ($h.metadata.PSObject.Properties.Name -contains 'source_file' -and $h.metadata.source_file) { $source = $h.metadata.source_file }
            if (-not $source -and $h.metadata.PSObject.Properties.Name -contains 'path' -and $h.metadata.path) { $source = $h.metadata.path }
            if (-not $source -and $h.metadata.PSObject.Properties.Name -contains 'file' -and $h.metadata.file) { $source = $h.metadata.file }
            if (-not $source -and $h.metadata.PSObject.Properties.Name -contains 'title' -and $h.metadata.title) { $source = $h.metadata.title }
          }
          if (-not $source -and $h.PSObject.Properties.Name -contains 'source' -and $h.source) { $source = $h.source }
          if (-not $source -and $h.PSObject.Properties.Name -contains 'id' -and $h.id) { $source = $h.id }

          Write-Host ("{0,2}. Score: {1,-10} | Quelle: {2}" -f $i, $score, $source)
          if($i -ge 10){ break }
        }
        $ok = $true; break
      } else {
        Write-Host "Hinweis: Endpoint antwortete, aber keine Trefferstruktur erkannt." -ForegroundColor DarkYellow
      }
    } catch {
      $status = $null
      try { $status = $_.Exception.Response.StatusCode.Value__ } catch {}
      if($status){ Write-Host ("Fehler {0} bei {1} {2}" -f $status, $t.Method, $url) -ForegroundColor Red }
      else{ Write-Host ("Fehler bei {0} {1}: {2}" -f $t.Method, $url, $_.Exception.Message) -ForegroundColor Red }
    }
  }
  if($ok){ break }
}

if(-not $ok){
  Write-Host "Kein kompatibler Endpoint gefunden oder Token/Header stimmen nicht für deine OWUI-Version." -ForegroundColor Red
  Write-Host "Tipp: Prüfe in OWUI → Settings → API Keys, ob 'x-api-key' erwartet wird, oder nutze die Logs." -ForegroundColor DarkGray
  exit 2
}
