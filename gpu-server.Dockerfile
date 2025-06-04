FROM nvidia/cuda:11.8.0-base-ubuntu22.04

# Install Python and basic tools
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Copy GPU server script
COPY gpu-server.py /app/gpu-server.py
WORKDIR /app

# Expose port
EXPOSE 9999

# Run the GPU server
CMD ["python3", "/app/gpu-server.py"]