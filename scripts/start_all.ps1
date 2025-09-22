# Startet OpenWebUI und Ollama Container
docker start openwebui -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) {
    docker run -d --name openwebui -p 3000:8080 ghcr.io/open-webui/open-webui:main
}

docker start ollama -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) {
    docker run -d --name ollama --gpus all -p 11434:11434 ollama/ollama:latest
}
