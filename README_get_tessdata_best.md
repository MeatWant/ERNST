# README – get_tessdata_best.ps1

Dieses PowerShell-Skript lädt Sprachmodelle aus dem offiziellen **tessdata_best** Repository von Tesseract OCR.  
`tessdata_best` enthält Modelle mit **höchster Genauigkeit** (langsamer, größer), im Gegensatz zu `tessdata` (Standard) oder `tessdata_fast` (schneller, weniger genau).

---

## Verwendung

### Standardaufruf
```powershell
.\get_tessdata_best.ps1
```
- Lädt **deu**, **eng** und **osd** nach `C:\Tesseract\tessdata_best\`.

### Zielordner und Sprachen angeben
```powershell
.\get_tessdata_best.ps1 -DestDir "D:\Apps\Tesseract\tessdata_best" -Langs deu,eng,osd
```

### Vorhandene Dateien überschreiben
```powershell
.\get_tessdata_best.ps1 -Force
```

### Umgebungsvariable setzen
```powershell
.\get_tessdata_best.ps1 -SetTessdataPrefix
```
- Setzt `TESSDATA_PREFIX` (User-Scope) auf den Elternordner von `DestDir`.  
- Beispiel: Bei `C:\Tesseract\tessdata_best` wird `TESSDATA_PREFIX=C:\Tesseract` gesetzt.  
- Dein OCR-Script erkennt den Pfad aber auch direkt über `--tessdata-dir`.

---

## Parameter

| Parameter | Typ | Standard | Beschreibung |
|-----------|-----|----------|--------------|
| `-DestDir` | string | `C:\Tesseract\tessdata_best` | Zielordner für Sprachmodelle |
| `-Langs` | string[] | `deu, eng, osd` | Liste der Sprachcodes |
| `-MaxRetries` | int | 3 | Maximale Versuche pro Download |
| `-Force` | switch | false | Überschreibt vorhandene Dateien |
| `-SetTessdataPrefix` | switch | false | Setzt Umgebungsvariable `TESSDATA_PREFIX` |

---

## Verifikation

Wenn Tesseract installiert ist und im PATH liegt, prüft das Skript nach dem Download die installierten Sprachen:
```powershell
tesseract --tessdata-dir <DestDir> --list-langs
```

Beispielausgabe:
```
List of available languages (3):
eng
deu
osd
```

---

## Hinweise

- Modelle stammen von: [tessdata_best GitHub](https://github.com/tesseract-ocr/tessdata_best)  
- Größe: pro Sprache zwischen 15 MB und 50 MB  
- Empfohlen: **deu**, **eng**, **osd**  
- Nutze `tessdata_best` für höchste Erkennungsqualität (z. B. UI-Screenshots mit Umlauten).

