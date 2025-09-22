# ERNST: Ensemble Retrieval for Neural Semantic Training

Mit ERNST können Sie verschiedene KI-Modelle verwenden, mit Hilfe von Ollama, um daraus automatisierte Bildunterschriften aus Screenshots zu generieren.
Die generierten Bildunterschriften werden in Markdown-Sidecar-Dateien gespeichert. Diese könnnen dann unter anderem in Dokumentationen eingebunden werden.

Hauptzweck ist jedoch die Verwendung der Bildunterschriften als Trainingsdaten, damit KI Modelle (Chatbots) mit Hilfe mit Retrieval-Augmented Generation (RAG) 
bessere Antworten auf Fragen zu einer bestimmten Software geben können.

ERNST läuft lokal in Docker-Containern und verwendet Ollama für die KI-Modelle.

# Installation und Nutzung

## Systemvoraussetzungen
- Windows 11 oder Linux (64-bit)
- Docker Desktop (mit GPU-Unterstützung, z. B. NVIDIA)
- Git + PowerShell (oder Bash)
- Hardware: NVIDIA GPU (12 GB+ VRAM empfohlen für Vision-Modelle wie LLaVA)

Ausführliche Anleitungen unter: [README_FULL.md](README_FULL.md)

Kenntnisse in Docker, PowerShell und KI-Modellen sind hilfreich.

## Quickstart

### Container starten

Startet Ollama und OpenWebUI (nicht zwingend, wenn nur Ollama genutzt wird):
Powershell im Projektverzeichnis öffnen und ausführen:

```powershell
.\scripts\start_all.ps1
```

### Modelle laden

Die Modelle werden mit folgendem Skript heruntergeladen und in Ollama geladen.
```powershell
.\scripts\pull_models.ps1
```
Andere Modelle können in `pull_models.ps1` ergänzt werden.

### Screenshots vorbereiten

Screenshots in `docs\screenshots\raw` ablegen.
- Format der Screenshots: PNG, JPG, JPEG, BMP, GIF
- Screenshots sollten nicht größer als 1-2 MB sein. (max. 1920x1080 empfohlen)
- Namenskonvention: `YYYYMMDD_Module_Screen_View.png` (z. B. `20250817_Agent_Chat_MainView.png`, `20250817_Browser_Search_Results.png`)

### Skript für Screenshots
Die Verarbeitung von Screenshots erfolgt mit:

```powershell
.\scripts\caption_screens_with_view.ps1 -DocsRoot "D:\KI\OpenWebUI\docs\screenshots" -Model "llava:7b" -OllamaUrl "http://127.0.0.1:11434"
```

Ausgabe:
- Markdown-Sidecars in `docs\screenshots\captions\`
- Index in `docs\screenshots\_index.md`

Erstellt 2025 von Stefan Roll, Verwendung auf eigene Gefahr.

Ursprünglich als Spaßprojekt gestartet, um die Möglichkeiten von KI-Modellen in der Dokumentationserstellung zu erkunden.
Jedoch: Aus Spaß wurde ERNST – und ERNST ist jetzt ein KI-Projekt.