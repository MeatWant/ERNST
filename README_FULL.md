# Screenshot-Dokumentation mit Ollama + Open WebUI

Dieses Projekt ermöglicht es, Screenshots von Benutzeroberflächen automatisch mit Beschreibungen zu versehen.  
Dazu wird ein Vision-Modell (z. B. `llava:7b`) in **Ollama** verwendet. Die Beschreibungen werden als **Markdown-Sidecars** gespeichert und in einem Index zusammengeführt.

---

## 1. Systemvoraussetzungen

### Hardware

-   GPU empfohlen: **NVIDIA RTX mit mindestens 8 GB VRAM**  
    (besser: ≥ 12 GB VRAM für größere Vision-Modelle)
-   CPU: mind. Quad-Core (Intel/AMD)
-   RAM: mindestens **16 GB**
-   Festplatte: **20 GB** freier Speicher für Modelle + Screenshots

### Software

-   **Windows 10/11**, Linux oder macOS
-   **Docker Desktop** (mit GPU-Support aktiviert)
-   **PowerShell 7.x** (für die Skripte)
-   **Open WebUI** (optional als Oberfläche für RAG & Suche)
-   **Ollama** (läuft im Container)

---

## 2. Installation & Einrichtung

1. **Verzeichnisstruktur anlegen**

    ```
    D:\KI\OpenWebUI\
      ├─ data\
      │   ├─ ollama\
      │   └─ openwebui\
      ├─ docker-compose.yaml
      ├─ docs\
      │   └─ screenshots\
      │        ├─ raw\        # Screenshots ablegen
      │        ├─ captions\   # Automatisch erzeugte Markdown-Dateien
      │        └─ _index.md   # Übersicht
      └─ scripts\
          └─ caption_screens_with_view.ps1
    ```

2. **Modelle laden**  
   Im Container:

    ```bash
    docker exec -it ollama ollama pull llava:7b
    ```

    (weitere Modelle nach Bedarf laden, z. B. `llava:13b`)

3. **Docker Compose (empfohlen)**  
   Datei `docker-compose.yaml`:
    ```yaml
    name: openwebui-ollama-stack

    networks:
      owui_net:
        name: owui_net         # fester Name, aber von Compose erstellt/verwaltet
        driver: bridge

    services:
      ollama:
        image: ollama/ollama:latest
        container_name: ollama
        restart: unless-stopped
        ports:
          - "11434:11434"
        volumes:
          - ./data/ollama:/root/.ollama
        environment:
          - OLLAMA_NUM_PARALLEL=2
          - OLLAMA_MAX_LOADED_MODELS=1
          - OLLAMA_KEEP_ALIVE=5m
        # <<< WICHTIG: GPU über 'deploy.resources.reservations.devices'     # GPU später aktivieren (Docker Desktop → Resources → GPU):
        deploy:
          resources:
            reservations:
              devices:
                - driver: nvidia
                  count: all
                  capabilities: ["gpu"]
        # robuster Healthcheck ohne curl/wget
        healthcheck:
          test: ["CMD", "sh", "-lc", "ollama list >/dev/null 2>&1 || exit 1"]
          interval: 10s
          timeout: 5s
          retries: 60
          start_period: 30s
        networks: [owui_net]    

      openwebui:
        image: ghcr.io/open-webui/open-webui:main
        container_name: openwebui
        restart: unless-stopped
        ports:
          - "3000:8080"
        volumes:
          - ./data/openwebui:/app/backend/data
        environment:
          - OLLAMA_BASE_URL=http://ollama:11434
          # optional: - WEBUI_AUTH=False
        depends_on:
          ollama:
            condition: service_healthy
        networks: [owui_net]
```

Starten:
```bash
docker compose up -d
```

4. **Alternative ohne Compose (nur Ollama starten)**
    ```bash
    docker run -d --name ollama --gpus all `
      -p 11434:11434 `
      -v "D:\KI\OpenWebUI\data\ollama:/root/.ollama" `
      -e OLLAMA_NUM_PARALLEL=1 `
      -e OLLAMA_MAX_LOADED_MODELS=1 `
      -e OLLAMA_KEEP_ALIVE=1m `
      ollama/ollama:latest
    ```

---

## 3. Verwendung der Skripte

### 3.1 Skript: `caption_screens_with_view.ps1`

Dieses Skript verarbeitet alle Screenshots in `raw\` und erzeugt für jedes Bild eine `.md`-Datei in `captions\`.  
Die Markdown-Dateien enthalten:

-   YAML-Frontmatter mit Metadaten (`module`, `screen`, `view`, `tags`)
-   automatisch generierte Beschreibung durch das Modell
-   Verweis auf den Screenshot

Außerdem wird eine Übersicht (`_index.md`) erstellt.

### 3.2 Aufruf

Parameter können je nach Bedarf angepasst werden. 
Standartaufruf: ohne Parameter werden die Defaults verwendet.

```powershell
.\caption_screens_with_view.ps1 `
  -DocsRoot "D:\KI\OpenWebUI\docs\screenshots" `
  -Model "llava:7b" `
  -OllamaUrl "http://127.0.0.1:11434" `
  -MaxRetries 2
  -Temperature 0.25 `
  -TopP 0.9 `
  -RepeatPenalty 1.1 `
  -NumCtx 8192
```

### 3.3 Parameter

Verfügbare Parameter:

-   `-DocsRoot` → Hauptverzeichnis der Screenshots
-   `-Model` → Vision-Modell in Ollama (`llava:7b`)
-   `-OllamaUrl` → URL des Ollama-Servers (`http://127.0.0.1:11434`)
-   `-Force` → Überschreibt vorhandene `.md`-Dateien
-   `-MaxRetries` → Anzahl Wiederholungen bei Fehlern
-   `-Temperature` → Sampling-Temperatur
-   `-TopP` → Nucleus Sampling
-   `-RepeatPenalty` → Bestrafung von Wiederholungen
-   `-NumCtx` → Maximale Kontextlänge (Tokens)

---

## 4. Ablauf

1. **Screenshots ablegen**

    - Dateien in `raw\` speichern
    - Namensschema:
        ```
        YYYYMMDD_Module_Screen_View.png
        ```

2. **Skript ausführen**

    - Erstellt `.md`-Dateien in `captions\`
    - Baut `_index.md` mit Übersicht

3. **Durchsuchen & Verwenden**
    - Dateien können direkt in **Open WebUI** oder einem anderen RAG-System indexiert werden.
    - Suche funktioniert über Texte, nicht über Bilder

---

## 5. Tipps & Empfehlungen

-   **Modelle**: für schnelle Tests `llava:7b`, für bessere Qualität `llava:13b`
-   **Speicher**: je größer das Modell, desto mehr VRAM benötigt wird
-   **RAG-Integration**: Nur die Markdown-Dateien indexieren, nicht die Bilder
-   **Logs prüfen**: bei Fehlern `docker logs ollama` und Payload-Dumps ansehen

---

## 6. Wartung

-   **Container stoppen**

    ```bash
    docker compose down
    ```

    oder bei manuellem Start:

    ```bash
    docker stop ollama
    ```

-   **Container löschen**

    ```bash
    docker rm -f ollama openwebui
    ```

-   **Logs ansehen**
    ```bash
    docker logs ollama
    docker logs openwebui
    ```

- **Modelle ansehen**
    ```bash
    docker exec -it ollama ollama list
    ```

- **Modelle entfernen**
    ```bash
    docker exec -it ollama ollama remove llava:7b
    ```
- **Modelle hinzufügen**
    ```bash
    docker exec -it ollama ollama pull llava:13b
    ```    
---

# Verfügbare Vision-Modelle für Ollama

Ollama unterstützt mehrere multimodale Modelle (Text + Bild), die für die Caption-Erstellung von Screenshots geeignet sind.  
Nachfolgend eine Übersicht der aktuell wichtigsten Modelle.

---

## LLaVA (Large Language-and-Vision Assistant)

LLaVA ist das populärste multimodale Modell in Ollama und wurde in der Version **1.6** veröffentlicht.  
Es verbessert Bildauflösung, OCR und visuelles Reasoning.

### Varianten

-   **llava:7b** – kompakt, schnelle Inferenz, 32K Kontext
-   **llava:13b** – höherwertige Bildbeschreibung, ca. doppelter Speicherbedarf
-   **llava:34b** – höchste Qualität, benötigt sehr viel VRAM

---

## Weitere Vision-Modelle

-   **bakllava-7b**  
    Basierend auf Mistral, liefert in der Praxis oft Ergebnisse vergleichbar mit `llava:13b`.

-   **llava-llama3**  
    LLaVA, trainiert auf **Llama 3-Instruct (8B)**.

-   **llava-phi3**  
    Sehr kleine Variante (3.8B), eignet sich für ressourcenschwache Systeme.

-   **minicpm-v**  
    Multimodales 8B-Modell, effizient für Vision-Language-Aufgaben.

-   **llama3.2-vision**  
    Verfügbar in **11B** und **90B** Parametern, Teil der Llama 3.2-Familie, mit starker Bildverarbeitungsfähigkeit.

- **qwen2.5vl:7b**  
    Neuere Alternative, 7B Parameter, gute OCR-Fähigkeiten.

- **mistral-small3.1:24b**  
    Multimodales 24B Modell, sehr VRAM-hungrig, aber mit guter Bildverarbeitung.

## Vergleichstabelle

| Modellname              | Größe (Params) | Downloadgröße | Kontext | Empfohlener VRAM | Bemerkung                                 |
| ----------------------- | -------------- | ------------- | ------- | ---------------- | ----------------------------------------- |
| **llava:7b**            | 7B             | ~4.7 GB       | 32K     | ≥ 8 GB           | Schnell, guter Einstieg                   |
| **llava:13b**           | 13B            | ~8 GB         | 4K      | ≥ 12 GB          | Bessere Qualität als 7B                   |
| **llava:34b**           | 34B            | ~20 GB        | 4K      | ≥ 24 GB          | Höchste Qualität, sehr VRAM-hungrig       |
| **bakllava-7b**         | 7B             | ~7 GB         | 4K      | ≥ 8 GB           | Community: oft vergleichbar mit llava:13b |
| **llava-llama3**        | 8B             | ~8 GB         | 4K      | ≥ 10 GB          | Neuere Basis (Llama 3)                    |
| **llava-phi3**          | 3.8B           | ~2 GB         | 4K      | ≥ 6 GB           | Sehr leichtgewichtig                      |
| **minicpm-v**           | 8B             | ~6 GB         | 4K      | ≥ 10 GB          | Alternative, effizient                    |
| **llama3.2-vision-11b** | 11B            | ~9 GB         | 4K      | ≥ 12 GB          | Moderne Architektur                       |
| **llama3.2-vision-90b** | 90B            | ~70 GB        | 4K      | ≥ 80 GB          | Nur für High-End/Cluster                  |
| **qwen2.5vl:7b**        | 7B             | ~6 GB         | 4K      | ≥ 8 GB           | Gute OCR-Fähigkeiten                      |
| **mistral-small3.1:24b** | 24B          | ~15 GB        | 4K      | ≥ 28 GB          | Sehr VRAM-hungrig, gute Bildverarbeitung  |

---

## 7. Beispiel Prompts für die Caption-Erstellung

Die Qualität der automatisch generierten Beschreibungen hängt stark vom verwendeten Prompt ab.  
Nachfolgend einige Beispiel-Prompts, die sich für UI-Screenshots bewährt haben.
Diese sind als Vorlage gedacht und können je nach Anwendungsfall angepasst werden.
Aktuell für `llava:7b`, `llava:13b`, `bakllava-7b` und ähnliche Modelle.

Unter Umständen sind Anpassungen nötig, da manche Modelle Probleme mit komplexen Anweisungen haben.
Außerdem können mit der Temperatur-Einstellung die Ergebnisse beeinflusst werden (siehe Abschnitt 9).

### Beispiel-Prompt V1: Detaillierte UI-Beschreibung

Relative gut funktionierender Prompt für llava-Modelle:

```
$instruction =  @(
'You are a technical writer. Carefully analyze the screenshot and provide a concise but detailed description in GERMAN language.',
'Context:',
'- Module: {{MODULE}}',
'- Screen: {{SCREEN}}',
'- View: {{VIEW}}',
'Instructions:',
'1. Begin with a short 1–2 sentence summary describing the purpose of this view.',
'2. List all clearly visible UI elements such as tables, buttons, input fields, labels, or messages. For each element, mention its function. If a list or table is present, summarize the shown rows (names, prices, status, totals).',
'3. Provide a step-by-step description of how a user would typically use this view.',
'4. Add notes if there are warnings, error messages, totals, prices, or other important information.',
'Important:',
'- Use only what is actually visible in the screenshot.',
'- Output must be in GERMAN.',
'- Do not invent features. If something is unclear, omit it.',
'- Use plain Markdown formatting as follows:',
'','# {Modul} – {Screen} – {View}',
'','**Zweck:** <summary in German>',
'','## Sichtbare UI-Elemente',
'- <Element – Funktion>',
'- <Element – Funktion>',
'','## Schritt-für-Schritt',
'1. <Aktion>',
'2. <Aktion>',
'3. <optional weitere Aktion>',
'','## Hinweise',
'- <Hinweis, Fehlermeldung, Berechtigung>'
) -join "`r`n"
```

### Beispiel-Prompt 2: Etwas umfassender

Hat eine gute Struktur, aber mit relative vielen Halluzinationen bei Modell: llava:13b.
Evtl. mit anderen Parametern (Temperature, TopP) probieren. Oder auch mit anderem Modell testen.

```
$instruction = @(
  'You are a technical writer. Analyze the UI screenshot strictly and produce a concise but detailed description.',
  'Output must be in **German**. Fill the sections with real content from the image only. **Do not print placeholders, examples, or angle brackets**.',
  '',
  'Rules:',
  '- Use only what is clearly visible. No assumptions.',
  '- If text is too small/blurred/hidden: write "unlesbar".',
  '- Preserve German UI text exactly (ä, ö, ü, ß), do not translate labels.',
  '- Use only ATX headings (#, ##). Do not repeat the title, do not use setext (===) headings.',
  '- Never print any of these strings: "<", ">", "Spalte1", "Wert", "erste sichtbare", "Warnungen/Fehlermeldungen".',
  '- If a section would be empty, write "n/a".',
  '',
  'Format (headings only, you must fill content):',
  '',
  '# {{MODULE}} - {{SCREEN}} - {{VIEW}}',
  '',
  '**Zweck:** (1–2 Sätze, nur das im Bild Erkennbare)',
  '',
  '## Sichtbare UI-Texte (wörtlich)',
  '- (Liste exakt sichtbarer Texte, jeweils in Backticks)',
  '',
  '## Sichtbare UI-Elemente',
  '- (Für jedes Element: Typ, Label, Funktion, Status falls sichtbar)',
  '- Tabelle (falls vorhanden): Spalten, 1 echte Beispielzeile, kurze Zusammenfassung',
  '',
  '## Schritt-für-Schritt',
  '1. (sichtbarer, naheliegender Schritt)',
  '2. (nächster Schritt)',
  '3. (weiterer Schritt oder "n/a")',
  '',
  '## Hinweise',
  '- (Warn-/Fehlermeldungen mit Originaltext in Backticks)',
  '- (Summen/Preise/Währungen, nur wenn sichtbar)',
  '- (Berechtigungen/Hinweise, nur wenn sichtbar)'
) -join "`r`n"

```

### Beispiel-Prompt 3: Stark erweitert

Kann Problem haben mit den Anweisungen, aber sehr ausführlich wenn es funktioniert:
Ausgabe ist mit `llava:13b` aktuell am schlechtesten, eigentlich nur Platzhaltertexte, wenn mit Standart Paramertern gearbeitet wird. (Temperatur, TopP, RepeatPenalty)

```
$instruction = @(
  'You are a technical writer. Analyze the UI screenshot strictly and produce a concise but detailed description.',
  'Think carefully first, then output only the final answer.',
  '',
  'Context:',
  '- Module: {{MODULE}}',
  '- Screen: {{SCREEN}}',
  '- View: {{VIEW}}',
  '',
  'General rules:',
  '- Use only what is clearly visible in the image. No assumptions.',
  '- If text is too small/blurred/hidden, write "unlesbar" (do not guess).',
  '- Preserve all original UI text exactly (including ä, ö, ü, ß). Do not translate UI labels.',
  '- Escape special Markdown characters in visible texts or wrap them in backticks.',
  '- Follow the structure and headings exactly. If a section would be empty, write "n/a".',
  '',
  'Output language: German (Deutsch only).',
  'Output format: Markdown exactly as below.',
  '',
  '# {{MODULE}} – {{SCREEN}} – {{VIEW}}',
  '',
  '**Zweck:** <1–2 Sätze, nur das im Bild Erkennbare>',
  '',
  '## Sichtbare UI-Texte (wörtlich)',
  '- `<exakt sichtbarer Text 1>`',
  '- `<exakt sichtbarer Text 2>`',
  '… (max. 30 Einträge; bei mehr als 30: "… (+N weitere)")',
  '',
  '## Sichtbare UI-Elemente',
  '- **Typ:** Button | Eingabefeld | Dropdown | Checkbox | Radiobutton | Tab | Link | Badge | Banner | Karte | Modal | Tooltip | **Tabelle**',
  '  - **Label:** `<sichtbarer Text oder "unlesbar">`',
  '  - **Funktion:** `<kurz, faktisch>`',
  '  - **Status (falls vorhanden):** enabled/disabled/active/warning/error/selected',
  '- **Tabelle** (falls vorhanden):',
  '  - **Spalten:** `[Spalte1, Spalte2, …]`',
  '  - **Beispielzeile:** `{Spalte1: Wert, Spalte2: Wert, …}`',
  '  - **Zusammenfassung sichtbarer Zeilen:** `<z. B. 12 Zeilen, davon 3 "Lieferbar">`',
  '',
  '## Schritt-für-Schritt',
  '1. `<erste sichtbare, naheliegende Nutzeraktion>`',
  '2. `<nächster sichtbarer Schritt>`',
  '3. `<weiterer sichtbarer Schritt oder "n/a">`',
  '',
  '## Hinweise',
  '- `<Warnungen/Fehlermeldungen/Banner mit Originaltext in Backticks>`',
  '- `<Summen/Preise/Währungen, nur wenn sichtbar>`',
  '- `<Berechtigungen/Hinweise, nur wenn sichtbar>`'
) -join "`r`n"

```

### Beispiel-Prompt 1 aber mit llama3.2-vision

Aufruf mit dem neuesten Modell `llama3.2-vision:11b` liefert aktuell vereinzelt die besten Ergebnisse.
Aber mit Vorsicht zu genießen, da die Ergebnisse sehr unterschiedlich sein können je nach Screenshot.

Aufruf mit angepassten Parametern:

```powershell
.\scripts\caption_screens_with_view.ps1 `
  -Model "llama3.2-vision:11b" `
  -NumPredict 1024 -NumCtx 4096 `
  -GpuLayers 999 -Temperature 0.2 `
  -Timing
```

Bringe mit Beispielpromt 1 bisher die besten Ergebnisse.

### Fazit Prompts und Modelle
- `llava:7b` und `bakllava-7b` funktionieren mit Beispiel-Prompt 1 am besten, aber mit kleineren Fehlern z.b. mit Übersetzungen.
- `llava:13b` fast noch am besten, mit diversen kleinen Schwierigkeiten.
- `llama3.2-vision:11b` kann mit Beispiel-Prompt 1 gute Ergebnisse liefern, aber sehr inkonsistent.
- `llava-llama3:latest` sehr unzuverlässig, oft nur Platzhaltertexte. Viel leerer Output. 

---

## 8. Empfehlung

-   Für **Tests**: `llava:7b` (geringer VRAM-Bedarf, solide Ergebnisse).
-   Für **ausgewogene Qualität**: `llava:13b` oder `bakllava-7b`.
-   Für **beste Präzision** (wenn genug VRAM vorhanden): `llava:34b` oder `llama3.2-vision-11b`.
-   Für **kleine Systeme**: `llava-phi3`.

---

## 9. Sampling-Parameter für die Modellsteuerung

Beim Erzeugen der Captions kann die Qualität und Stabilität der Ergebnisse durch **Sampling-Parameter** gezielt gesteuert werden.  
Diese Parameter werden beim Aufruf des Skripts `caption_screens_with_view.ps1` übergeben und wirken sich direkt auf das Verhalten des Vision-Modells aus.

### Übersicht der Parameter

| Parameter        | Typ   | Standard | Wirkung                                                                                           | Empfehlung für UI-Captions             |
| ---------------- | ----- | -------- | ------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `-Temperature`   | Float | 0.25     | Steuert die Kreativität des Modells. Niedrig = deterministisch, hoch = kreativer, aber riskanter. | 0.2–0.4 für präzise Beschreibungen     |
| `-TopP`          | Float | 0.9      | Nucleus Sampling: Begrenzung auf die wahrscheinlichsten Tokens. 1.0 = keine Begrenzung.           | 0.9 als guter Standard                 |
| `-RepeatPenalty` | Float | 1.1      | Bestraft Wiederholungen. Höher = weniger Dopplungen, aber riskant für Listen.                     | 1.1–1.2 für stabile Listen             |
| `-NumCtx`        | Int   | 8192     | Maximale Kontextlänge (Tokens). Bestimmt, wie viel Text/Tabellen der Prompt+Output umfassen darf. | 4096–8192, je nach Modellunterstützung |

### Auswirkungen im Detail

-   **Temperature**

    -   Niedrig (0.1–0.3): Sehr präzise, kaum Halluzinationen, aber manchmal knapp im Ausdruck.
    -   Mittel (0.4–0.6): Mehr Variation, etwas freier.
    -   Hoch (0.7–1.0): Kreativ, aber bei UI-Beschreibungen Gefahr von erfundenen Elementen.

-   **TopP**

    -   Senkt man unter 0.8, wird das Modell noch deterministischer.
    -   Bei 1.0 entfällt die Begrenzung, was zu „bunteren“ Antworten führen kann.

-   **RepeatPenalty**

    -   Werte < 1.0 fördern Wiederholungen.
    -   Werte > 1.3 können dazu führen, dass auch erwünschte Wiederholungen (z. B. Tabellenzeilen) abgeschnitten werden.

-   **NumCtx**
    -   Wichtig für Screenshots mit langen Tabellen oder komplexen UI-Elementen.
    -   Reicht der Kontext nicht, werden Inhalte abgeschnitten oder fehlen in der Beschreibung.

### Beispielaufruf

```powershell
.\caption_screens_with_view.ps1 `
  -DocsRoot "D:\KI\OpenWebUI\docs\screenshots" `
  -Model "llava:13b" `
  -Temperature 0.2 `
  -TopP 0.9 `
  -RepeatPenalty 1.1 `
  -NumCtx 8192
```

---

## 10. Upcoming / Future Enhancements

Für das Script `caption_screens_with_view.ps1` sind folgende Erweiterungen geplant, um die Qualität und Verwertbarkeit der Ergebnisse weiter zu verbessern:

1. **Sampling-Optimierung**
   - [x] Unterstützung für anpassbare Parameter (`-Temperature`, `-TopP`, `-RepeatPenalty`, `-NumCtx`).
      - Ziel: bessere Balance zwischen Genauigkeit (weniger Halluzinationen) und Stabilität (saubere Listen, konsistente Ausgabe).

2. **Modell-Vergleiche**
   - Test weiterer Vision-Modelle neben `llava:13b`, z. B.:
     - `bakllava:7b` (leichter, teilweise präzisere UI-Texterkennung),
     - `llama3.2-vision-11b` (bessere OCR-Fähigkeiten),
     - `llava-phi3` (kompakt, stabil für reine UI-Texte).
   - Ziel: Finden des optimalen Trade-offs zwischen VRAM-Bedarf und Output-Qualität.

3. **Zusätzliches Output-Format (JSON)**
   - Neben Markdown-Sidecars (`.md`) auch strukturierte JSON-Ausgabe (`.json`) je Screenshot.
   - Vorteil: maschinelle Weiterverarbeitung (z. B. gezielte Suche nach Buttons, Tabellen oder Fehlermeldungen).
   - Langfristig: Kombination von JSON + Markdown für sowohl maschinelle Analyse als auch menschliche Lesbarkeit.

4. **OCR-Integration**
   - Optionale Vorschaltung eines OCR-Tools (z. B. Tesseract).
   - Aufgabe: Extraktion der reinen UI-Texte aus Screenshots → Übergabe dieser an das Modell für präzisere Struktur-Beschreibung.
   - Ziel: Minimierung von „unlesbar“-Einträgen und Reduktion von Halluzinationen.

5. **Strengere Prompt-Varianten**
   - Einführung einer alternativen Prompt-Vorlage (`$instruction_strict`), die auf maximale Faktentreue ausgelegt ist.
   - Einsatz als Fallback, falls das Modell Platzhalter oder Spekulationen ausgibt.

---


## Rechtliches

Alle Modelle sind Open Source, die Nutzung unterliegt den jeweiligen Lizenzbedingungen der Entwickler.
Docker-Images von Ollama sind proprietär, aber die Modelle selbst sind frei verfügbar.
Die Nutzung erfolgt auf eigenes Risiko.

Alle nicht genannten Marken- und Produktnamen sind Eigentum der jeweiligen Inhaber.

Script- und Dokumentationserstellung: Stefan Roll (2025)
Nutzung erfolgt auf eigenes Risiko.
---
