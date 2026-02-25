#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa in: $(pwd)"

# 3. Windows / macOS 不支持
if [ "$OS_TYPE" == "windows" ] || [ "$OS_TYPE" == "macos" ]; then
    log_warn "bwa v0.7.19 Windows/macOS build is NOT SUPPORTED"
    log_warn "Use minimap2 instead for these platforms"
    exit 0
fi

# 4. Linux 构建
export CFLAGS="-g -Wall -Wno-unused-function -O3"
export LIBS="-lm -lz -lpthread -lrt"

log_info "Building for Linux..."

make clean 2>/dev/null || true
make -j${MAKE_JOBS}

# 5. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bwa "${INSTALL_PREFIX}/bin/"

# 6. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa installed to ${INSTALL_PREFIX}/bin/"
