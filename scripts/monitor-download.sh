#!/bin/bash
# Monitor download progress by watching file size

MODEL_FILE="/opt/ai-box/models/stable-diffusion/SDXL/cyberrealistic-pony-v6.safetensors"
EXPECTED_SIZE_GB=6.5  # Expected model size in GB

echo "📊 Monitoring download progress for: $(basename "$MODEL_FILE")"
echo "🎯 Expected size: ~${EXPECTED_SIZE_GB}GB"
echo "📁 Path: $MODEL_FILE"
echo ""
echo "Press Ctrl+C to stop monitoring"
echo "----------------------------------------"

while true; do
    if [ -f "$MODEL_FILE" ]; then
        # Get file size in bytes and convert to human readable
        SIZE_BYTES=$(stat -c%s "$MODEL_FILE" 2>/dev/null || echo 0)
        SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
        SIZE_GB=$(echo "scale=2; $SIZE_MB / 1024" | bc -l 2>/dev/null || echo "0")
        
        # Calculate percentage if we know expected size
        EXPECTED_BYTES=$(echo "$EXPECTED_SIZE_GB * 1024 * 1024 * 1024" | bc -l)
        PERCENT=$(echo "scale=1; $SIZE_BYTES * 100 / $EXPECTED_BYTES" | bc -l 2>/dev/null || echo "0")
        
        # Create progress bar
        PROGRESS_WIDTH=30
        FILLED=$(echo "scale=0; $PERCENT * $PROGRESS_WIDTH / 100" | bc -l 2>/dev/null || echo "0")
        FILLED=${FILLED%.*}  # Remove decimal part
        
        printf "\r🔄 Progress: ["
        for ((i=1; i<=PROGRESS_WIDTH; i++)); do
            if [ $i -le $FILLED ]; then
                printf "█"
            else
                printf " "
            fi
        done
        printf "] %s%% (%s MB / %.1f GB)" "$PERCENT" "$SIZE_MB" "$SIZE_GB"
        
        # Check if download is complete
        if (( $(echo "$SIZE_GB >= $EXPECTED_SIZE_GB" | bc -l) )); then
            echo ""
            echo "✅ Download appears complete! Final size: ${SIZE_GB}GB"
            break
        fi
    else
        printf "\r⏳ Waiting for download to start..."
    fi
    
    sleep 2
done