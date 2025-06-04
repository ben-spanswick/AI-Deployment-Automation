#!/bin/bash
# Download a basic Stable Diffusion model

echo "Downloading Stable Diffusion v1.5 model..."
echo "This will take a few minutes depending on your internet speed."

# Create directory if it doesn't exist
mkdir -p /opt/ai-box/models/stable-diffusion 2>/dev/null || {
    echo "Note: Cannot create directory without sudo. Please run:"
    echo "sudo mkdir -p /opt/ai-box/models/stable-diffusion"
    echo "sudo chown -R $USER:$USER /opt/ai-box/models"
    exit 1
}

# Download SD 1.5 model (pruned version, ~4GB)
wget -c -P /opt/ai-box/models/stable-diffusion/ \
    https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors

echo "Download complete!"
echo "Restarting Forge to load the model..."
docker restart forge

echo "SD Forge should now be accessible at http://localhost:7860"