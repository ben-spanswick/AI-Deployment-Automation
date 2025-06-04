#!/bin/bash
# Download CyberRealistic Pony SDXL Model

MODEL_DIR="/opt/ai-box/models/stable-diffusion/SDXL"
MODEL_FILE="cyberrealistic-pony-v6.safetensors"
DOWNLOAD_URL="https://civitai.com/api/download/models/495395"

echo "🎨 Downloading CyberRealistic Pony SDXL model..."
echo "📁 Target: $MODEL_DIR/$MODEL_FILE"

# Create directory if it doesn't exist
mkdir -p "$MODEL_DIR"

# Try different download methods
echo "🔄 Attempting download..."

# Method 1: Direct curl with proper headers
curl -L \
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
  -o "$MODEL_DIR/$MODEL_FILE" \
  "$DOWNLOAD_URL"

if [ $? -eq 0 ] && [ -f "$MODEL_DIR/$MODEL_FILE" ]; then
    echo "✅ Download successful!"
    echo "📊 File size: $(du -h "$MODEL_DIR/$MODEL_FILE" | cut -f1)"
    echo "🎯 Model ready for Forge at: $MODEL_DIR/$MODEL_FILE"
else
    echo "❌ Download failed. Please try manual download:"
    echo "   1. Visit: https://civitai.com/models/443821/cyberrealistic-pony"
    echo "   2. Download the .safetensors file"
    echo "   3. Save to: $MODEL_DIR/$MODEL_FILE"
fi