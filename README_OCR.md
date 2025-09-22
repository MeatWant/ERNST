# README – OCR-Pipeline (Tesseract → JSON/RAG)

Dieses PowerShell-Skript führt OCR auf UI-Screenshots aus, fusioniert die Ergebnisse mit vorhandenen Vision-Markdown-Sidecars und erzeugt mehrere Sidecar-Artefakte für RAG:
Dies ist eine erweiterung des captioning-Skripts aus unserem vorliegenden [README_FULL.md](README_FULL.md) Projekt und konzentriert sich speziell auf die OCR-Pipeline mit Tesseract.
Es nutzt Tesseract OCR (v5+) mit mehreren Fallbacks, um die bestmögliche Texterkennung zu erzielen.

Die erzeugten Rag-Dateien enthalten den erkannten Text, Metadaten und eine Zusammenfassung der UI-Elemente, die für Retrieval-Augmented Generation (RAG) nützlich sind.

**Voraussetzung ist, dass die Screenshots in einem definierten Ordner liegen und optional bereits Vision-Markdown-Sidecars vorhanden sind.**

## Outputs

- `captions\ocr_tmp\<name>.txt/.tsv` – Roh-OCR (Text/TSV)  
- `captions\<name>.json` – strukturierte JSON-Zusammenfassung (OCR + Vision + Meta)  
- `captions\<name>.rag.txt` – zeilenorientiertes, RAG-freundliches Textformat  
- `captions\<name>.norm.txt` – normalisierter Suchtext (lowercased, Umlaute vereinheitlicht)

## Voraussetzungen
- **Windows** mit PowerShell 5+ (getestet) oder PowerShell 7  
- **Tesseract** im `PATH` (oder `--tessdata-dir` verwendbar)  
- **ImageMagick** (`magick.exe`) empfohlen für Preprocessing  
- Screenshots liegen unter `docs\screenshots\raw\`

Empfohlene Struktur:
```
D:\KI\OpenWebUI\docs\screenshots\
  ├─ raw\         # Input-Bilder (.png/.jpg/.webp/.tif/.tiff)
  └─ captions\    # Output (JSON / RAG / NORM), inkl. ocr_tmp\
```

---

## Konfigurations-Variablen (im Skriptkopf)

> Diese Werte kannst du direkt im Skript anpassen.  
> Optional kannst du sie auch als **Parameter** führen (siehe weiter unten „Als Parameter aufrufen“).

| Variable              | Zweck |
|-----------------------|------|
| `$BaseDir`            | Basisordner, standardmäßig: `D:\KI\OpenWebUI\docs\screenshots` |
| `$RawDir`             | Bilder-Ordner = `$BaseDir\raw` |
| `$CaptionsDir`        | Ausgabepfad = `$BaseDir\captions` |
| `$TessDataBest`       | Pfad zu `tessdata_best` (optional). Wenn vorhanden ⇒ `--tessdata-dir` gesetzt |
| `$UseBest`            | Wird automatisch `true`, wenn `$TessDataBest` existiert |
| `$TessOEM`            | Tesseract OEM, Standard `3` |
| `$TessPSM`            | Erster PSM im Erstpass, Standard `6` |
| `$LangPrimary`        | Primäre OCR-Sprache, Standard `"deu"` |
| `$LangMixed`          | Mixed-Lang, Standard `"deu+eng"` |
| `$TryMixedLang`       | Mixed-Lang in Fallbacks erlauben? Standard `true` |
| `$PsmCandidates`      | PSM-Liste für Fallback-Sweep: `@(6,12,3,4,11,7)` |
| `$MinConfTarget`      | Qualitätsziel (Ø-Konfidenz der Wörter), Standard `60` |
| `$MinConfForBlocks`   | Schwelle für „gute“ Wörter in Statistiken, Standard `50` |
| `$MaxBlocksToKeep`    | Limit für gewertete Wörter (Performance), Standard `5000` |
| `$ImagePatterns`      | Dateimuster: `*.png, *.jpg, *.jpeg, *.webp, *.tif, *.tiff` |
| `$UsePreprocess`      | Preprocessing mit ImageMagick/NET aktivieren, Standard `true` |

**Tesseract-Configs (im Aufruf gesetzt):**
- `preserve_interword_spaces=1` (Spacing behalten)  
- `user_defined_dpi=300`  
- `load_system_dawg=0`, `load_freq_dawg=0` (ohne Lexikon)  
- `thresholding_method=2`

> Hinweis: Wenn du öfter OCR-Fehlablesungen bei deutschen Umlauten siehst, könntest du testweise `load_*_dawg` wieder aktivieren.

---

## Was macht das Skript genau?

1) **Preprocessing** (optional)  
   - Mit ImageMagick: Graustufen, DPI 300, 200% Upscale, Kontrast, leichtes Unsharp.  
   - Fallback: .NET-Basisskalierung (nur Windows).

2) **Erster OCR-Pass**  
   - `lang=deu`, `psm=6`, OEM 3. Schreibt `.txt` + `.tsv`.

3) **Qualitätsmessung**  
   - Berechnung von `conf_avg_all` (alle Wörter) und `conf_avg_filtered` (nur Wörter ≥ 50).

4) **Fallback-Suche (wenn nötig)**  
   - Sweep über `PSM`-Kandidaten und Sprachen (`deu`, optional `deu+eng`) am **vorverarbeiteten** Bild.  
   - Bestes Ergebnis gewinnt (erst `conf_used`, dann `conf_all`).  
   - Wenn keine Verbesserung, **Finalversuche** am **Originalbild**: `psm=11/6` (deu) und einmal `psm=12` (deu+eng).

5) **Vision-Merge**  
   - Liest vorhandene Vision-Markdown-Sidecars (`captions\<name>.md`), extrahiert Frontmatter (module/screen/view/tags/captured_at/image/source_file) und „Zweck“/„Sichtbare UI-Elemente“.

6) **Outputs**  
   - **JSON** (`captions\<name>.json`): OCR (Text + Konfidenzen + Params), Vision (Summary + UI + Tags), Meta (SHA-1, Größe).  
   - **RAG Flat** (`captions\<name>.rag.txt`): kompaktes Plain-Text-Format inkl. OCR-Text.  
   - **NORM** (`captions\<name>.norm.txt`): für Volltextsuche normalisiert (lowercase, Umlaute→ae/oe/ue/ss, Sonderzeichen entfernt).

---

## Ausführung

### Standard
- Lege deine Screenshots in `raw\` ab.
- Starte das Skript (PowerShell im Projektordner):
```powershell
.\scripts\ocr_screens_tesseract.ps1
```
> Der Scriptname ist beliebig; nutze den tatsächlichen Dateinamen, z. B. `ocr_screens_tesseract.ps1`.

### Typische Logausgaben
```
[DIR] RAW=D:\KI\OpenWebUI\docs\screenshots\raw | CAPTIONS=D:\KI\OpenWebUI\docs\screenshots\captions | OCR_TMP=...
[INFO] Using ImageMagick: C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe
[OCR] (1/9) Start: D:\...\20250913_Dashboard_Shop_Startseite.png
[OCR] First pass: lang=deu, psm=6
  conf_avg_all=42, conf_avg_filtered=55
  Low quality -> fallback search (target 60)...
  Fallback chosen: lang=deu+eng, psm=12, conf_used=61, conf_all=58
  Reading image metadata...
  Meta: 1920x1080, sha1:...
  RAG flat written -> ...\captions\...\*.rag.txt
[OK] 1/9  20250913_Dashboard_Shop_Startseite.png  ->  ...\captions\...\*.json
```

> **Hinweis:** Tesseract-Interne Hinweise („OSD: Weak margin…“) siehst du nicht, weil die Tesseract-Ausgabe unterdrückt wird (`Out-Null`), um saubere ASCII-Logs zu behalten.

---

## (Optional) Als Parameter aufrufen

Wenn du die **Hard-Codes in echte Parameter** umbaust (empfohlen), könntest du z. B. so starten:

```powershell
.\ocr_pipeline.ps1 `
  -BaseDir "D:\KI\OpenWebUI\docs\screenshots" `
  -UsePreprocess:$true `
  -LangPrimary "deu" `
  -TryMixedLang:$true `
  -MinConfTarget 60 `
  -TessDataBest "C:\Tesseract\tessdata_best"
```

**Beispiel-Param-Definition (Anregung für’s Skript):**
```powershell
param(
  [string]$BaseDir = "D:\KI\OpenWebUI\docs\screenshots",
  [switch]$UsePreprocess = $true,
  [string]$LangPrimary = "deu",
  [string]$LangMixed = "deu+eng",
  [switch]$TryMixedLang = $true,
  [int]$MinConfTarget = 60,
  [int]$TessOEM = 3,
  [int]$TessPSM = 6,
  [string]$TessDataBest = "C:\Tesseract\tessdata_best"
)
```

---

## Fehlerbilder & Tipps

- **„No TXT produced – skipping file.“**  
  Tesseract konnte keine Ausgabe erzeugen → prüfe Bild, Pfade, Rechte, `tesseract.exe` im PATH.
- **Geringe Konfidenzen trotz Fallbacks**  
  Teste mit *aktivierten DAWGs* (entferne `load_*_dawg=0`), `psm` anpassen, oder Preprocessing variieren.
- **ImageMagick fehlt**  
  Skript fällt automatisch auf .NET-Upscale zurück (langsamer/limitierter).
- **Umlaute in Suche**  
  Für Suche nutze `*.norm.txt` – dort sind Umlaute bereits vereinheitlicht.


---

## Beispielaufrufe für `ocr_screens_tesseract.ps1`

### 1) Standardlauf (deu, Preprocessing an)
```powershell
.\ocr_screens_tesseract.ps1 `
  -BaseDir "D:\KI\OpenWebUI\docs\screenshots" `
  -UsePreprocess `
  -LangPrimary "deu" `
  -TessOEM 3 -TessPSM 6 `
  -MinConfTarget 60
```
→ Solide Qualität, Fallbacks nur wenn Ø-Konfidenz < 60.

### 2) Schnelllauf (ohne Preprocessing)
```powershell
.\ocr_screens_tesseract.ps1 -BaseDir "D:\KI\OpenWebUI\docs\screenshots" -UsePreprocess:$false -LangPrimary "deu" -MinConfTarget 55
```
→ Deutlich schneller, geringere Genauigkeit.

### 3) Qualitätsmodus (aggressiver Fallback-Sweep)
```powershell
.\ocr_screens_tesseract.ps1 -BaseDir "D:\KI\OpenWebUI\docs\screenshots" -UsePreprocess -LangPrimary "deu" -TryMixedLang -LangMixed "deu+eng" -PsmCandidates 6,12,3,4,11,7 -MinConfTarget 65 -MinConfForBlocks 40
```
→ Testet viele PSM/Sprachen, bessere Resultate, aber langsamer.

### 4) Englisch-UIs
```powershell
.\ocr_screens_tesseract.ps1 -BaseDir "D:\KI\OpenWebUI\docs\screenshots" -UsePreprocess -LangPrimary "eng" -TryMixedLang:$false -MinConfForBlocks 60
```
→ Rein englisch, strenger Wortfilter.

### 5) Misch-UIs (deu/eng)
```powershell
.\ocr_screens_tesseract.ps1 -BaseDir "D:\KI\OpenWebUI\docs\screenshots" -UsePreprocess -LangPrimary "deu" -TryMixedLang -LangMixed "deu+eng" -MinConfTarget 58
```
→ Für gemischte Benutzeroberflächen.

### 6) Archiv/TIFF-Batch
```powershell
.\ocr_screens_tesseract.ps1 -BaseDir "E:\Archive\Screens" -UsePreprocess -ImagePatterns "*.png","*.jpg","*.jpeg","*.tif","*.tiff" -PsmCandidates 6,11,12 -MaxBlocksToKeep 8000
```
→ Größere Formate eingeschlossen, genauere Statistik.

### 7) Mit `tessdata_best`
```powershell
.\ocr_screens_tesseract.ps1 -BaseDir "D:\KI\OpenWebUI\docs\screenshots" -UsePreprocess -TessDataBest "C:\Tesseract\tessdata_best" -LangPrimary "deu" -TryMixedLang -LangMixed "deu+eng"
```
→ Nutzt hochwertigere Sprachmodelle.

### 8) Debug-Lauf
```powershell
.\ocr_screens_tesseract.ps1 -BaseDir "D:\KI\OpenWebUI\docs\screenshots" -UsePreprocess -Verbose
```
→ Zeigt zusätzliche Tesseract-Ausgaben.

---

## Parameter und Wirkung

| Parameter | Typ | Default | Wirkung auf Qualität | Wirkung auf Geschwindigkeit | Bemerkungen |
|-----------|-----|---------|----------------------|-----------------------------|-------------|
| `-BaseDir` | string | `D:\…\docs\screenshots` | – | – | Root für `raw\` & `captions\`. |
| `-UsePreprocess` | switch | true | ↑ bessere Lesbarkeit | ↓ etwas langsamer | 200% Upscale, 300 DPI, Graustufe, Kontrast. |
| `-LangPrimary` | string | `deu` | ↑ wenn Sprache passt | – | Hauptsprache im Erstpass. |
| `-TryMixedLang` | switch | true | ↑ bei gemischten UIs | ↓ | Aktiviert zusätzlich `-LangMixed`. |
| `-LangMixed` | string | `deu+eng` | ↑ gemischte UIs | ↓ | Kombination deutsch/englisch. |
| `-TessOEM` | int | 3 | variabel | variabel | 3 = Standardengine. |
| `-TessPSM` | int | 6 | ↑ wenn Layout passt | – | Start-Layoutmodus (6 = Block of text). |
| `-PsmCandidates` | int[] | 6,12,3,4,11,7 | ↑ Gründlichkeit | ↓ mehr Versuche | Testet weitere Layoutmodi. |
| `-MinConfTarget` | int | 60 | ↑ Qualität, mehr Fallbacks | ↓ langsamer | Zielwert für Ø-Konfidenz. |
| `-MinConfForBlocks` | int | 50 | ↑/↓ je nach Wert | – | Filter für Statistik-Wörter. |
| `-MaxBlocksToKeep` | int | 5000 | – | ↑ falls kleiner | Begrenzung für Statistik. |
| `-ImagePatterns` | string[] | gängige Bildformate | – | je nach Menge | Welche Bildtypen verarbeitet werden. |
| `-TessDataBest` | string | – | ↑ bessere Erkennung | ↓ minimal langsamer | Optionales `tessdata_best`. |

**Faustregeln:**  
- Für Qualität: `UsePreprocess` an, `TryMixedLang` an, PSM-Liste erweitern, `MinConfTarget` erhöhen.  
- Für Tempo: `UsePreprocess` aus, PSM-Liste kürzen, `MinConfTarget` senken.

---
