# 📖 Runbook – Screenshot → Caption → OCR → RAG

## 1. Umgebung starten

```powershell
.\start_all.ps1      # Docker-Services starten (Ollama, OpenWebUI)
.\pull_models.ps1    # Modelle ziehen (Vision, Embeddings, Reranker …)
```

Prüfen, ob Container laufen:  
```powershell
docker ps
```

---

## 2. Screenshots vorbereiten

- Screenshots in `docs\screenshots\raw\` ablegen  
- Namensschema empfohlen:
  ```
  YYYYMMDD_Module_Screen_View.png
  ```

---

## 3. Captions erzeugen (Vision-Modell)

```powershell
.\caption_screens_with_view.ps1 `
  -DocsRoot "D:\KI\OpenWebUI\docs\screenshots" `
  -Model "llava:13b" `
  -OllamaUrl "http://127.0.0.1:11434"
```

**Output:**  
- `captions\*.md` (Markdown-Sidecars mit Frontmatter + Beschreibung)  
- `_index.md` (Übersicht)

---

## 4. OCR laufen lassen (Tesseract)

```powershell
.\ocr_screens_tesseract.ps1 `
  -BaseDir "D:\KI\OpenWebUI\docs\screenshots" `
  -UsePreprocess `
  -LangPrimary "deu" `
  -TryMixedLang `
  -LangMixed "deu+eng" `
  -TessDataBest "C:\Tesseract\tessdata_best"
```

**Output (pro Screenshot):**  
- `captions\ocr_tmp\*.txt/.tsv` → Roh-OCR  
- `captions\*.json` → OCR + Vision + Meta (Debug)  
- `captions\*.rag.txt` → **Hauptquelle für RAG**  
- `captions\*.norm.txt` → Optional für Hybrid-Suche

---

## 5. RAG-Ingestion in OpenWebUI

Nur diese Dateien indexieren:  
- **Pflicht:** `*.rag.txt`  
- **Optional:** `*.md` (Semantik), `*.norm.txt` (Keyword/Hybrid)  
- **Nie:** `*.json`, `ocr_tmp\*`

Empfohlene Einstellungen:  
- Chunk Size: 800–1000 Tokens, Overlap 100–150  
- Retriever Top-k: 8

---

## 6. Health-Checks

Anzahl prüfen:
```powershell
$cap = "D:\KI\OpenWebUI\docs\screenshots\captions"
$raw = "D:\KI\OpenWebUI\docs\screenshots\raw"

"{0} images | {1} rag | {2} md | {3} json | {4} norm" -f `
 (Get-ChildItem $raw -File | Measure-Object).Count, `
 (Get-ChildItem $cap -Filter *.rag.txt -File | Measure-Object).Count, `
 (Get-ChildItem $cap -Filter *.md -File | Measure-Object).Count, `
 (Get-ChildItem $cap -Filter *.json -File -File | Measure-Object).Count, `
 (Get-ChildItem $cap -Filter *.norm.txt -File | Measure-Object).Count
```

OCR-Qualität stichprobenartig:
```powershell
$sample = Get-ChildItem $cap -Filter *.rag.txt | Select-Object -First 1
Get-Content $sample.FullName -Raw | Select-String -Pattern 'OCR \(lang=.*conf_avg=\d+\)'
```

---

## 7. Embeddings & Reranker

- Embeddings: Erzeuge Vektoren aus `*.rag.txt`-Chunks (z. B. mit BGE oder E5).  
- Retriever: FAISS/Milvus oder integriertes Backend von OpenWebUI.  
- Reranker: z. B. `BAAI/bge-reranker-v2-m3`.  

Beispiel-Test (Python, Reranker):
```python
from FlagEmbedding import FlagReranker
m = FlagReranker('BAAI/bge-reranker-v2-m3', use_fp16=True)
pairs = [
  ['Einkaufsmanagement Artikelliste', 'Artikelliste mit Preisen und Bestellnummern'],
  ['Einkaufsmanagement Artikelliste', 'Urlaubskalender der Belegschaft']
]
print(m.compute_score(pairs))
```

---

## 8. Nächste Schritte

### Spezielle Verwendung mit PHP Anwendungen
- 🔒 Hash-Verknüpfung & Zugriffsschutz über `.htaccess` + PHP → später nachziehen.  
- ⚙️ Parameter-Tuning (OCR, Sampling, Retriever) → nach Bedarf.  
- 📊 Monitoring: DB-Größe, OCR-Qualität, Modell-Output.

---

Alle nicht genannten Marken- und Produktnamen sind Eigentum der jeweiligen Inhaber.

Script- und Dokumentationserstellung: Stefan Roll (2025)
Nutzung erfolgt auf eigenes Risiko.