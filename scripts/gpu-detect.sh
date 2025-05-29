#!/bin/bash
# gpu-detect.sh - Detect NVIDIA GPU configuration

# Initialize variables
GPU_COUNT=0
GPU_MODEL="Unknown"
GPU_MEMORY=0
GPU_DRIVER_VERSION=""
CUDA_VERSION=""

# Arrays for multiple GPUs
declare -a GPU_MODELS
declare -a GPU_MEMORIES
declare -a GPU_UUIDS

# Check if nvidia-smi is available
if command -v nvidia-smi &> /dev/null; then
    # Get GPU count
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
    
    # Get driver version
    GPU_DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    
    # Get information for each GPU
    for i in $(seq 0 $((GPU_COUNT-1))); do
        GPU_MODELS[$i]=$(nvidia-smi --id=$i --query-gpu=name --format=csv,noheader)
        GPU_MEMORIES[$i]=$(nvidia-smi --id=$i --query-gpu=memory.total --format=csv,noheader,nounits)
        GPU_UUIDS[$i]=$(nvidia-smi --id=$i --query-gpu=uuid --format=csv,noheader)
    done
    
    # Set primary GPU info
    GPU_MODEL="${GPU_MODELS[0]}"
    GPU_MEMORY="${GPU_MEMORIES[0]}"
    
    # Check CUDA version
    if command -v nvcc &> /dev/null; then
        CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $6}' | cut -d',' -f1)
    elif [[ -f /usr/local/cuda/version.txt ]]; then
        CUDA_VERSION=$(cat /usr/local/cuda/version.txt | awk '{print $3}')
    fi
    
elif command -v lspci &> /dev/null; then
    # Fallback to lspci
    GPU_COUNT=$(lspci | grep -i nvidia | grep -i vga | wc -l)
    
    if [[ $GPU_COUNT -gt 0 ]]; then
        # Get first GPU model
        GPU_MODEL=$(lspci | grep -i nvidia | grep -i vga | head -1 | sed 's/.*: //' | sed 's/ (.*)//')
        
        # Try to detect all GPU models
        i=0
        while read -r line; do
            GPU_MODELS[$i]=$(echo "$line" | sed 's/.*: //' | sed 's/ (.*)//')
            ((i++))
        done < <(lspci | grep -i nvidia | grep -i vga)
    fi
fi

# Function to get GPU topology
get_gpu_topology() {
    if command -v nvidia-smi &> /dev/null && [[ $GPU_COUNT -gt 1 ]]; then
        echo "GPU Topology:"
        nvidia-smi topo -m 2>/dev/null || echo "  Topology information not available"
    fi
}

# Function to check GPU compute capability
check_compute_capability() {
    if command -v nvidia-smi &> /dev/null; then
        echo "GPU Compute Capabilities:"
        for i in $(seq 0 $((GPU_COUNT-1))); do
            local cc=$(nvidia-smi --id=$i --query-gpu=compute_cap --format=csv,noheader 2>/dev/null)
            if [[ -n "$cc" ]]; then
                echo "  GPU $i: Compute Capability $cc"
            fi
        done
    fi
}

# Function to check GPU memory
check_gpu_memory() {
    if command -v nvidia-smi &> /dev/null; then
        echo "GPU Memory Configuration:"
        for i in $(seq 0 $((GPU_COUNT-1))); do
            local total=$(nvidia-smi --id=$i --query-gpu=memory.total --format=csv,noheader 2>/dev/null)
            local used=$(nvidia-smi --id=$i --query-gpu=memory.used --format=csv,noheader 2>/dev/null)
            local free=$(nvidia-smi --id=$i --query-gpu=memory.free --format=csv,noheader 2>/dev/null)
            echo "  GPU $i: Total: $total, Used: $used, Free: $free"
        done
    fi
}

# Function to suggest GPU assignment based on memory
suggest_gpu_assignment() {
    if [[ $GPU_COUNT -eq 0 ]]; then
        echo "No GPUs detected for assignment"
        return
    fi
    
    echo "Suggested GPU Assignment:"
    
    if [[ $GPU_COUNT -eq 1 ]]; then
        echo "  Single GPU detected - all services will share GPU 0"
        echo "  Consider reducing model sizes or running services sequentially"
    elif [[ $GPU_COUNT -eq 2 ]]; then
        echo "  Text Generation: GPU 0"
        echo "  Stable Diffusion: GPU 1"
        echo "  FastAPI: GPU 0,1 (can access both)"
    else
        # For 3+ GPUs
        echo "  Text Generation: GPU 0"
        echo "  Stable Diffusion: GPU 1"
        echo "  FastAPI: GPU 0,1"
        echo "  Additional GPUs ($(seq 2 $((GPU_COUNT-1)) | paste -sd,)): Available for scaling"
    fi
}

# Export variables if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export GPU_COUNT
    export GPU_MODEL
    export GPU_MEMORY
    export GPU_DRIVER_VERSION
    export CUDA_VERSION
    export GPU_MODELS
    export GPU_MEMORIES
    export GPU_UUIDS
fi

# Display information if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== NVIDIA GPU Detection ==="
    echo
    echo "GPU Count: $GPU_COUNT"
    
    if [[ $GPU_COUNT -gt 0 ]]; then
        echo "Driver Version: ${GPU_DRIVER_VERSION:-Not detected}"
        echo "CUDA Version: ${CUDA_VERSION:-Not detected}"
        echo
        echo "Detected GPUs:"
        for i in $(seq 0 $((GPU_COUNT-1))); do
            echo "  GPU $i: ${GPU_MODELS[$i]:-Unknown}"
            if [[ -n "${GPU_MEMORIES[$i]}" ]]; then
                echo "    Memory: ${GPU_MEMORIES[$i]} MB"
            fi
            if [[ -n "${GPU_UUIDS[$i]}" ]]; then
                echo "    UUID: ${GPU_UUIDS[$i]}"
            fi
        done
        echo
        check_compute_capability
        echo
        check_gpu_memory
        echo
        get_gpu_topology
        echo
        suggest_gpu_assignment
    else
        echo "No NVIDIA GPUs detected!"
        echo
        echo "Possible reasons:"
        echo "  - NVIDIA drivers not installed"
        echo "  - No NVIDIA GPUs present"
        echo "  - GPUs not properly seated"
        echo
        echo "Try running: lspci | grep -i nvidia"
    fi
fi