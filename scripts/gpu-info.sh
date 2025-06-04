#!/bin/bash
# gpu-info.sh - Provide GPU information via API

case "$1" in
    "system")
        # Get GPU basic info
        if command -v nvidia-smi &> /dev/null; then
            driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
            cuda=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}')
            gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
            
            # Get GPU names
            gpu_names=$(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd,)
            
            echo "{\"driver\":\"$driver\",\"cuda\":\"$cuda\",\"count\":$gpu_count,\"names\":\"$gpu_names\"}"
        else
            echo "{\"error\":\"nvidia-smi not found\"}"
        fi
        ;;
    "metrics")
        # Get GPU metrics
        if command -v nvidia-smi &> /dev/null; then
            echo "["
            nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits | \
            awk -F',' '{
                if (NR > 1) printf ","
                printf "{\"index\":%d,\"name\":\"%s\",\"temperature\":%s,\"gpu_util\":%s,\"mem_used\":%s,\"mem_total\":%s,\"power_draw\":%s}", 
                $1, $2, $3, $4, $5, $6, $7
            }'
            echo "]"
        else
            echo "[]"
        fi
        ;;
    *)
        echo "Usage: $0 {system|metrics}"
        exit 1
        ;;
esac