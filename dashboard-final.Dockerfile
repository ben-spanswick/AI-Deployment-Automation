FROM python:3.9-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y curl docker.io && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir flask==2.3.3

# Copy the dashboard script from build context
COPY dashboard-unified.py /app/dashboard.py
COPY chromadb-info.html /app/chromadb-info.html
COPY ollama-info.html /app/ollama-info.html

EXPOSE 80

CMD ["python", "-u", "dashboard.py"]