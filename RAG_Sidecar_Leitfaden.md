# RAG-Sidecar-Leitfaden (pro Screenshot)

> **Kurzfassung:** Für das Retrieval in OpenWebUI nutzen wir **pro Screenshot genau *eine* Hauptdatei**: `\<name>.rag.txt`.  
> Alles andere sind Metadaten/Beifang für Debugging bzw. optionale Booster.

---

## Artefakte, die das Pipeline-Skript erzeugt

Verzeichnis: `...\docs\screenshots\captions\`

| Datei | Inhalt/Zweck | In RAG indizieren? |
|---|---|---|
| `\<name>.rag.txt` | **Flacher Text** mit Metadaten (image/module/screen/view/size/hash) **+ kompletter OCR-Text**. | **Ja (empfohlen, die Hauptquelle)** |
| `\<name>.md` | Kuratierte Vision-Beschreibung mit Frontmatter (module/screen/view/tags/captured_at/…). | **Optional** (zusätzliche Semantik, falls gewünscht) |
| `\<name>.json` | Strukturierte Fusion (Vision + OCR + Meta). Nützlich für Debug/Analysen / spätere Features. | **Nein** (macht den Index „noisy“) |
| `\<name>.norm.txt` | Normalisierte Stichwort-Variante (z. B. ä→ae, ß→ss) zur Keyword/Haystack-Suche. | **Nur**, wenn OWUI **Hybrid/Keyword-Suche** nutzt. |

Verzeichnis: `...\docs\screenshots\captions\ocr_tmp\`

| Datei | Inhalt/Zweck | In RAG indizieren? |
|---|---|---|
| `\<name>.txt` | Roh-OCR (Volltext von Tesseract). | **Nein** (Zwischenablage) |
| `\<name>.tsv` | OCR mit BBox/Confidence pro Token/Word. | **Nein** (Zwischenablage) |

---

## Warum genau so?

- **RAG braucht Text** – `.rag.txt` ist bewusst **kompakt und ingestierbar** (kein JSON-Overhead).
- **`.md`** bringt kuratierte Semantik (Beschreibung, Struktur), ist aber **nicht zwingend**, wenn `.rag.txt` bereits alle wichtigen Inhalte enthält.
- **`.json`** enthält hilfreiche Struktur für Debug und spätere Auswertungen (Qualität, Hash, Maße), **gehört aber nicht in den Vektorindex**.
- **`.norm.txt`** verbessert **nur** reine Keyword/Hybrid-Suchen. Für reine Embeddings ist sie unnötig.

---

## Beispiel: Inhalt `\<name>.rag.txt`

```text
image: 20250913_Dashboard_Shop_Startseite.png
module: Shop
screen: Dashboard
view: Startseite
captured_at: 2025-09-13T10:42:00Z
hash: sha1:60f5d2f2cb10b289a8a3d1342c6d5851b8c6c48e
size: 1920x1080

SUMMARY:
Kurze, kuratierte Beschreibung des Screens …

UI_ELEMENTS:
- Warenkorb
- Bestellen
- Filter …

OCR (lang=deu+eng, oem=1, psm=6, conf_avg=72):
[Hier der von Tesseract erkannte Wortlaut …]
```

> **Hinweis:** Für das eigentliche Beantworten von Fragen (Zitate, Button-Beschriftungen) ist der **OCR-Block** entscheidend. Die Metadaten dienen zur besseren Kontextualisierung.

---

## Empfohlenes Vorgehen (Reihenfolge)

1. Screenshots nach `...\docs\screenshots\raw\` legen.
2. Vision-Sidecars (`\<name>.md`) wie gehabt erzeugen/pflegen (optional).
3. OCR-Skript ausführen → erzeugt `ocr_tmp\*.txt|*.tsv`, `\<name>.json`, `\<name>.rag.txt`, `\<name>.norm.txt`.
4. **In RAG/KG (OpenWebUI) ingestieren:**  
   - Minimal: `*.rag.txt`  
   - Optional zusätzlich: `*.md` (mehr Semantik), `*.norm.txt` (wenn Hybrid-Search aktiv ist).
5. (Optional) `ocr_tmp\` nach erfolgreichem Index-Build leeren.

---

## Klein, aber wichtig (Ingestion-Hinweise)

- **File-Globs in OWUI:** `*.rag.txt, *.md` (und **nur** falls gewünscht: `*.norm.txt`).  
- **Chunking:** 800–1000 Tokens, Overlap 100–150.  
- **Retriever-Top‑k:** 8 (später nach Bedarf feinjustieren).  
- **Keine `*.json` ingestieren.**

---

## Health-Checks (PowerShell Snippets)

```powershell
$cap = "D:\KI\OpenWebUI\docs\screenshots\captions"
$raw = "D:\KI\OpenWebUI\docs\screenshots\raw"

"{0} images | {1} rag | {2} md | {3} json | {4} norm" -f `
 (Get-ChildItem $raw -File | Measure-Object).Count, `
 (Get-ChildItem $cap -Filter *.rag.txt -File | Measure-Object).Count, `
 (Get-ChildItem $cap -Filter *.md -File | Measure-Object).Count, `
 (Get-ChildItem $cap -Filter *.json -File | Measure-Object).Count, `
 (Get-ChildItem $cap -Filter *.norm.txt -File | Measure-Object).Count
```

```powershell
# Spot-Check: OCR-Qualität eines Beispiels aus rag.txt
$sample = Get-ChildItem $cap -Filter *.rag.txt | Select-Object -First 1
Get-Content $sample.FullName -Raw | Select-String -Pattern 'OCR \(lang=.*conf_avg=\d+\)'
```

---

## FAQ

- **Brauche ich `.md` zwingend?**  
  Nein. `.rag.txt` reicht. `.md` kann aber semantische Treffer verbessern (z. B. „wo finde ich …“).

- **Warum nicht `.json` ins RAG?**  
  JSON-Strukturen erzeugen Rauschen und verschlechtern die semantische Nachbarschaft. Text schlägt Struktur hier.

- **Wozu `.norm.txt`?**  
  Nur für Keyword/Hybrid-Suche relevant (Diakritika neutralisieren, exakte Matches). Für reine Embeddings nicht nötig.
