#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa in: $(pwd)"

# 3. Windows 不支持
if [ "$OS_TYPE" == "windows" ]; then
    log_warn "bwa v0.7.19 Windows build is NOT SUPPORTED"
    log_warn "This version (0.7.19) has serious Windows compatibility issues"
    log_warn "Consider using bwa-mem2 or a newer version"
    exit 0
fi

# 4. 非 Windows 平台
export CFLAGS="-g -Wall -Wno-unused-function -O3"
export LIBS="-lm -lz -lpthread"

case "${OS_TYPE}" in
    "macos")
        log_info "Building for macOS..."
        [ -d "/opt/homebrew/opt/zlib" ] && export CFLAGS="${CFLAGS} -I/opt/homebrew/opt/zlib/include"
        [ "${ARCH_TYPE}" == "arm64" ] && export CFLAGS="${CFLAGS} -arch arm64"
        ;;
    
    "linux")
        log_info "Building for Linux..."
        export LIBS="${LIBS} -lrt"
        export LDFLAGS="-static"
        ;;
esac

make clean 2>/dev/null || true
make -j${MAKE_JOBS}

# 5. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bwa${EXE_EXT} "${INSTALL_PREFIX}/bin/"

# 6. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa installed to ${INSTALL_PREFIX}/bin/"
