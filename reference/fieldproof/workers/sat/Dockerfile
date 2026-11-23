# worker-sat Fieldproof (ADR-0005) — Python 3.12 ; rasterio embarque GDAL dans sa roue.
FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt ./
# libexpat : requise par le GDAL embarqué dans la roue rasterio, absente de l'image slim
RUN apt-get update && apt-get install -y --no-install-recommends libexpat1 && rm -rf /var/lib/apt/lists/*
RUN pip install -r requirements.txt
COPY sat ./sat
RUN useradd --create-home worker
USER worker
CMD ["python", "-m", "sat.main"]
