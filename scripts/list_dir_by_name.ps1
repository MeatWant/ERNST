# List directories by name

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $Root = "D:\dein\repo"
)

$bad = "node_modules","vendor",".git","dist","build",".next",".nuxt",".vite","coverage","storage","var","logs","cache"
Get-ChildItem $Root -Directory -Recurse | Where-Object { $bad -contains $_.Name } | Select-Object FullName
