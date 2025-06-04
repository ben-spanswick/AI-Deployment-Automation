#!/bin/bash
# Diagnose SD Forge CUDA issues

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=== SD Forge CUDA Diagnostics ===${NC}\n"

# 1. System CUDA info
echo -e "${BLUE}1. System CUDA Information:${NC}"
echo "Driver CUDA Version: $(nvidia-smi | grep "CUDA Version" | sed -n 's/.*CUDA Version: \([0-9]*\.[0-9]*\).*/\1/p')"
echo "CUDA Toolkit Installations:"
ls -la /usr/local/ | grep cuda || echo "No CUDA installations found"
echo

# 2. Current Forge status
echo -e "${BLUE}2. Forge Container Status:${NC}"
docker ps -a | grep forge || echo "No forge container found"
echo

# 3. Forge environment
echo -e "${BLUE}3. Forge Container Environment:${NC}"
if docker ps | grep -q forge; then
    echo "CUDA visibility in container:"
    docker exec forge nvidia-smi 2>&1 || echo "nvidia-smi failed in container"
    echo
    echo "Python/PyTorch environment:"
    docker exec forge python -c "
import sys
print(f'Python: {sys.version}')
try:
    import torch
    print(f'PyTorch: {torch.__version__}')
    print(f'CUDA available: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'CUDA version: {torch.version.cuda}')
        print(f'cuDNN version: {torch.backends.cudnn.version()}')
        print(f'GPU count: {torch.cuda.device_count()}')
        for i in range(torch.cuda.device_count()):
            print(f'GPU {i}: {torch.cuda.get_device_name(i)}')
except Exception as e:
    print(f'Error: {e}')
" 2>&1 || echo "Python test failed"
else
    echo "Forge container is not running"
fi
echo

# 4. Forge logs analysis
echo -e "${BLUE}4. Forge Error Analysis:${NC}"
if docker logs forge 2>&1 | grep -q "RuntimeError.*CUDA"; then
    echo -e "${RED}CUDA/PyTorch errors detected:${NC}"
    docker logs forge 2>&1 | grep -A2 -B2 "RuntimeError" | tail -20
elif docker logs forge 2>&1 | grep -q "torch.*cuda"; then
    echo -e "${RED}Torch/CUDA compatibility issues detected:${NC}"
    docker logs forge 2>&1 | grep -i "torch.*cuda" | tail -10
else
    echo "No obvious CUDA errors in logs"
fi
echo

# 5. Libraries check
echo -e "${BLUE}5. CUDA Libraries Check:${NC}"
echo "Host CUDA 12.1 libraries:"
ls -la /usr/local/cuda-12.1/lib64/libcudart.so* 2>/dev/null | head -5 || echo "CUDA 12.1 libraries not found"
echo

# 6. Recommendations
echo -e "${YELLOW}=== Recommendations ===${NC}"
if docker logs forge 2>&1 | grep -q "Your device does not support"; then
    echo "1. The Forge image has incompatible PyTorch/CUDA versions"
    echo "2. Try mounting CUDA 12.1 libraries into the container"
    echo "3. Run: sudo ./scripts/fix-forge-cuda.sh"
elif ! docker ps | grep -q forge; then
    echo "1. Forge container is not running"
    echo "2. Check logs with: docker logs forge"
    echo "3. Try restarting with: docker restart forge"
fi