#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa-mem2 in: $(pwd)"

# 3. 检查子模块
if [ ! -d "ext/safestringlib" ] || [ ! -f "ext/safestringlib/Makefile" ]; then
    log_info "Initializing git submodules..."
    git submodule update --init --recursive
fi

# 4. ARM 不支持
if [ "$ARCH_TYPE" == "arm64" ]; then
    log_warn "bwa-mem2 does not support ARM64"
    exit 0
fi

# 5. macOS 不支持（safestringlib 与 SDK 冲突）
if [ "$OS_TYPE" == "macos" ]; then
    log_warn "bwa-mem2 macOS build is NOT SUPPORTED"
    log_warn "safestringlib conflicts with modern macOS SDK"
    exit 0
fi

# 6. 平台适配
case "${OS_TYPE}" in
    "windows")
        log_info "Building for Windows..."
        export CXX="g++"
        export CC="gcc"
        export CXXFLAGS="-g -O3 -fpermissive -static-libgcc -static-libstdc++"
        
        make clean 2>/dev/null || true
        make -j${MAKE_JOBS} portable=1
        ;;
    
    "linux")
        log_info "Building for Linux x86_64..."
        
        export CXXFLAGS="-g -O3 -fpermissive -static-libgcc -static-libstdc++"
        
        # 检测 SIMD
        if grep -q "avx512" /proc/cpuinfo 2>/dev/null; then
            export ARCH="avx512"
        elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
            export ARCH="avx2"
        elif grep -q "avx" /proc/cpuinfo 2>/dev/null; then
            export ARCH="avx"
        else
            export ARCH="sse42"
        fi
        
        make clean 2>/dev/null || true
        make -j${MAKE_JOBS} portable=1 arch=${ARCH}
        ;;
esac

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"

if [ -f "bwa-mem2${EXE_EXT}" ]; then
    cp -f "bwa-mem2${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
elif [ -f "bwa-mem2" ]; then
    cp -f bwa-mem2 "${INSTALL_PREFIX}/bin/"
fi

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa-mem2${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa-mem2 installed to ${INSTALL_PREFIX}/bin/"
