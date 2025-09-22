

# PowerShell: Dateitypen im Projektverzeichnis nach Größe sortieren

```
$root = "D:\dein\repo"
Get-ChildItem $root -Recurse -File |
  Group-Object Extension | Sort-Object Count -Descending |
  Select-Object @{n="Ext";e={$_.Name}}, Count, @{n="MB";e={[math]::Round(($_.Group | Measure-Object Length -Sum).Sum/1MB,1)}}
```

# PowerShell: Verzeichnisse mit bestimmten Namen im Projektverzeichnis finden

```
$root = "D:\dein\repo"
$bad = "node_modules","vendor",".git","dist","build",".next",".nuxt",".vite","coverage","storage","var","logs","cache"
Get-ChildItem $root -Directory -Recurse | Where-Object { $bad -contains $_.Name } | Select-Object FullName
```

