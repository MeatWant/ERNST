# Installation des BAAI/bge-reranker-v2-m3 in Open WebUI (Docker)

Diese Anleitung beschreibt die Schritte, wie wir den **BAAI/bge-reranker-v2-m3** Reranker erfolgreich im Open WebUI Docker-Container installiert haben.

---

## Voraussetzungen

- Laufender Docker-Container für Open WebUI (z. B. Service `openwebui` in `docker-compose.yml`).
- Internetzugang für den Container, um Modelle von Hugging Face herunterzuladen.

---

## Schritte

### 1. Persistent Cache konfigurieren

In der `docker-compose.yml` wurde ein persistenter Cache für Hugging Face eingerichtet:

```yaml
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - HF_HOME=/root/.cache/huggingface
    volumes:
      - ./data/openwebui:/app/backend/data
      - ./data/hf-cache:/root/.cache/huggingface
```

Dann den Container neu starten:

```bash
docker compose up -d
```

### 2. Paket installieren und Reranker laden

Mit folgendem Befehl wurde **FlagEmbedding** installiert und das Modell heruntergeladen:

```powershell
docker exec -it openwebui bash -lc "pip install -U FlagEmbedding huggingface_hub && export HF_HOME=/root/.cache/huggingface && python - <<'PY'
from FlagEmbedding import FlagReranker
m = FlagReranker('BAAI/bge-reranker-v2-m3', use_fp16=True)
print('OK: downloaded and cached')
PY"
```

### 3. Überprüfung des Downloads

Prüfen, ob die Modell-Dateien im Cache liegen:

```bash
docker exec -it openwebui ls -lhR /root/.cache/huggingface
```

### 4. Reranker testen

Ein kurzer Test direkt im Container:

```bash
docker exec -it openwebui python - <<'PY'
from FlagEmbedding import FlagReranker
m = FlagReranker("BAAI/bge-reranker-v2-m3", use_fp16=True)
print("✅ Reranker geladen:", m.model_dir)
print("Testscore:", m.compute_score(["Das ist ein Test", "Noch ein Satz"]))
PY
```

---

## Ergebnis

- Das Modell **BAAI/bge-reranker-v2-m3** wurde erfolgreich in den Container heruntergeladen und in einem persistenten Hugging Face Cache gespeichert.
- Mit dem Testskript konnte bestätigt werden, dass der Reranker korrekt geladen wird.

---

## Nächste Schritte

- Integration in die Open WebUI Konfiguration (Admin Settings → Documents → Reranking Model).  
- Anpassung der PowerShell-Testskripte, um den neuen Reranker über die API zu nutzen.
