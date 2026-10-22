# Nur Hub, the NAS side of the Nur app: pairing, system status, Docker apps, web search, model downloads and a
# proxy to llama.cpp / Ollama. Built for linux/arm64 (Raspberry Pi 4/5) and linux/amd64.
# It runs in container mode: host commands go through nsenter, so the container needs pid: host,
# network_mode: host and privileged: true (see docker-compose.yml). Without those it only sees itself.
FROM python:3.13-slim

LABEL org.opencontainers.image.title="Nur Hub" \
      org.opencontainers.image.description="NAS service for the Nur app: pairing, system status, Docker control, web search, local model downloads and an OpenAI-compatible proxy to llama.cpp and Ollama." \
      org.opencontainers.image.version="1.1.3"

# nsenter (util-linux) runs commands in the host's namespaces. No Docker CLI in the image: the host's own
# docker, vcgencmd, nmcli and smartctl are used.
RUN apt-get update \
 && apt-get install -y --no-install-recommends util-linux \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY nur_hub.py catalog.json /app/

ENV NUR_HUB_CONTAINER=1 \
    NUR_HUB_STATE_DIR=/var/lib/nur-hub \
    NUR_HUB_PORT=8770 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

VOLUME ["/var/lib/nur-hub"]
EXPOSE 8770

HEALTHCHECK --interval=30s --timeout=6s --start-period=10s --retries=3 \
  CMD python -c "import os,urllib.request;urllib.request.urlopen('http://127.0.0.1:%s/api/v1/info' % os.environ.get('NUR_HUB_PORT','8770'), timeout=5)" || exit 1

ENTRYPOINT ["python", "/app/nur_hub.py"]
