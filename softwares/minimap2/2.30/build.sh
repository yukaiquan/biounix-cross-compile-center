#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building minimap2 in: $(pwd)"

# 3. 准备编译参数
# minimap2 默认 Makefile 使用 CC, CFLAGS, LIBS
MAKE_OPTS=""
EXTRA_LDFLAGS="-lz -lpthread -lm"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Optimization for Windows (MSYS2)..."
        # Windows 静态编译
        export CFLAGS="-O3 -static"
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        # Windows 下通常不需要特殊指令集开关，Makefile 会自动检测
        ;;

    "macos")
        log_info "Optimization for macOS..."
        [ -d "/opt/homebrew/opt/zlib" ] && ZDIR="/opt/homebrew/opt/zlib" || ZDIR="/usr/local/opt/zlib"
        export CFLAGS="-O3 -I${ZDIR}/include"
        export LDFLAGS="-L${ZDIR}/lib"
        
        if [ "${ARCH_TYPE}" == "arm64" ]; then
            log_info "Enabling NEON for macOS ARM64 (M1/M2/M3)"
            MAKE_OPTS="arm_neon=1 aarch64=1"
        fi
        ;;

    "linux")
        export CFLAGS="-O3"
        if [ "${ARCH_TYPE}" == "arm64" ]; then
            if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
                log_info "Cross-compiling for Linux ARM64..."
                export CC="aarch64-linux-gnu-gcc"
                export AR="aarch64-linux-gnu-ar"
                MAKE_OPTS="arm_neon=1 aarch64=1"
                export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
            else
                log_info "Native Linux ARM64 build..."
                MAKE_OPTS="arm_neon=1 aarch64=1"
                export LDFLAGS="-static"
            fi
        else
            export LDFLAGS="-static"
        fi
        ;;
esac

# 5. 执行编译
log_info "Running: make clean"
make clean || true

log_info "Running: make -j${MAKE_JOBS} ${MAKE_OPTS}"
make -j${MAKE_JOBS} ${MAKE_OPTS}

# 6. 编译额外工具 (如 sdust)
log_info "Building extra tools (sdust)..."
make sdust

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f minimap2${EXE_EXT} "${INSTALL_PREFIX}/bin/"
cp -f sdust${EXE_EXT} "${INSTALL_PREFIX}/bin/"

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/minimap2${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful! Binary format:"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "minimap2 and sdust installed to ${INSTALL_PREFIX}/bin/"
