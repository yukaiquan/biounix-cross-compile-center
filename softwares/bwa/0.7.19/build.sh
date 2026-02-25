#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa in: $(pwd)"

# 3. 编译参数（基于原版 Makefile）
export CFLAGS="-g -Wall -Wno-unused-function -O3"
export LDFLAGS="-lm -lz -lpthread"

# 4. 平台适配
case "${OS_TYPE}" in
    "windows")
        log_info "Building for Windows (MSYS2)..."
        export CFLAGS="${CFLAGS} -static"
        export LDFLAGS="${LDFLAGS} -static-libgcc -static-libstdc++"
        
        # Windows 使用 gcc
        export CC="gcc"
        ;;
    
    "macos")
        log_info "Building for macOS..."
        # macOS 使用 clang
        export CC="clang"
        
        # 链接 zlib（Homebrew）
        if [ -d "/opt/homebrew/opt/zlib" ]; then
            export CFLAGS="${CFLAGS} -I/opt/homebrew/opt/zlib/include"
            export LDFLAGS="${LDFLAGS} -L/opt/homebrew/opt/zlib/lib"
        elif [ -d "/usr/local/opt/zlib" ]; then
            export CFLAGS="${CFLAGS} -I/usr/local/opt/zlib/include"
            export LDFLAGS="${LDFLAGS} -L/usr/local/opt/zlib/lib"
        fi
        
        # ARM64 需要特殊处理
        if [ "${ARCH_TYPE}" == "arm64" ]; then
            log_info "Building for macOS ARM64 (Apple Silicon)"
            # Makefile 会在检测到 ARM64 时自动使用合适参数
        fi
        ;;
    
    "linux")
        log_info "Building for Linux..."
        
        # Linux 添加 -lrt（时钟函数）
        export LDFLAGS="${LDFLAGS} -lrt"
        
        # 静态链接
        export LDFLAGS="${LDFLAGS} -static"
        
        # 根据编译器选择
        if command -v clang &>/dev/null; then
            export CC="clang"
            log_info "Using clang compiler"
        else
            export CC="gcc"
            log_info "Using gcc compiler"
        fi
        
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

# 导出环境变量
export CFLAGS
export LDFLAGS

# 5. 编译
log_info "Running: make clean"
make clean 2>/dev/null || true

log_info "Running: make -j${MAKE_JOBS} CC=${CC}"
make -j${MAKE_JOBS} CC="${CC}"

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bwa${EXE_EXT} "${INSTALL_PREFIX}/bin/"

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
    ls -la "$FINAL_BIN"
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa installed to ${INSTALL_PREFIX}/bin/"
