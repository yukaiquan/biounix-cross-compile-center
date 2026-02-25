#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa in: $(pwd)"

# 3. 准备编译参数
export CFLAGS="-g -Wall -O3"
export LDFLAGS="-lm -lz -lpthread"

# 4. 平台适配
case "${OS_TYPE}" in
    "windows")
        log_info "Building for Windows (MSYS2)..."
        export CFLAGS="${CFLAGS} -static"
        export LDFLAGS="${LDFLAGS} -static-libgcc -static-libstdc++"
        ;;
    
    "macos")
        log_info "Building for macOS..."
        # macOS 使用系统 zlib
        if [ -d "/opt/homebrew/opt/zlib" ]; then
            export CFLAGS="${CFLAGS} -I/opt/homebrew/opt/zlib/include"
            export LDFLAGS="${LDFLAGS} -L/opt/homebrew/opt/zlib/lib"
        elif [ -d "/usr/local/opt/zlib" ]; then
            export CFLAGS="${CFLAGS} -I/usr/local/opt/zlib/include"
            export LDFLAGS="${LDFLAGS} -L/usr/local/opt/zlib/lib"
        fi
        ;;
    
    "linux")
        log_info "Building for Linux..."
        export LDFLAGS="${LDFLAGS} -static -lrt"
        
        # ARM64 交叉编译
        if [ "${ARCH_TYPE}" == "arm64" ]; then
            if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
                log_info "Cross-compiling for Linux ARM64..."
                export CC="aarch64-linux-gnu-gcc"
                export AR="aarch64-linux-gnu-ar"
            fi
        fi
        ;;
esac

# 5. 编译
log_info "Running: make clean"
make clean || true

log_info "Running: make -j${MAKE_JOBS}"
make -j${MAKE_JOBS}

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bwa${EXE_EXT} "${INSTALL_PREFIX}/bin/"

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa installed to ${INSTALL_PREFIX}/bin/"
