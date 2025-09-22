param(
  [string]$WebUiUrl = "http://localhost:3000",
  [string]$Query    = "Finde die Artikelliste im Einkaufsmanagement"
)

$targets = @(
  @{ Method="GET";  Url="/api/search";         QueryParam="q" },
  @{ Method="GET";  Url="/api/rag/search";     QueryParam="q" },
  @{ Method="GET";  Url="/api/v1/search";      QueryParam="q" },
  @{ Method="POST"; Url="/api/retrieval/query"; Body=@{query=$Query;top_k=8;rerank=$true} },
  @{ Method="POST"; Url="/api/rag/query";       Body=@{query=$Query;top_k=8;rerank=$true} },
  @{ Method="POST"; Url="/api/v1/rag/query";    Body=@{query=$Query;top_k=8;rerank=$true} }
)

Write-Host ("==> Open WebUI Base: {0}" -f $WebUiUrl) -ForegroundColor Cyan
Write-Host ("==> Query          : {0}" -f $Query)     -ForegroundColor Yellow

Add-Type -AssemblyName System.Web

foreach ($t in $targets) {
  $fullUrl = $WebUiUrl.TrimEnd('/') + $t.Url
  try {
    if ($t.Method -eq "GET") {
      $uri = $fullUrl + "?" + ($t.QueryParam + "=" + [System.Web.HttpUtility]::UrlEncode($Query))
      Write-Host ("-- TRY {0} {1}" -f $t.Method, $uri) -ForegroundColor DarkCyan
      $resp = Invoke-RestMethod -Uri $uri -Method GET -TimeoutSec 10
    } else {
      $bodyJson = ($t.Body | ConvertTo-Json -Depth 6)
      Write-Host ("-- TRY {0} {1}" -f $t.Method, $fullUrl) -ForegroundColor DarkCyan
      $resp = Invoke-RestMethod -Uri $fullUrl -Method POST -TimeoutSec 10 -Body $bodyJson -ContentType "application/json"
    }

    if ($null -eq $resp) { throw "Empty response" }

    Write-Host "Raw JSON:" -ForegroundColor DarkGray
    ($resp | ConvertTo-Json -Depth 8) | Out-String | Write-Host

    Write-Host "------------ schema keys -------------" -ForegroundColor DarkGray
    if ($resp.PSObject.Properties.Name) {
      $resp.PSObject.Properties.Name -join ", " | Write-Host
    }

    Write-Host "`n"
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
