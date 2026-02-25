#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa-mem2 in: $(pwd)"

# 检查是否需要初始化子模块
if [ ! -d "ext/safestringlib" ] || [ ! -f "ext/safestringlib/Makefile" ]; then
    log_info "Initializing git submodules..."
    git submodule update --init --recursive
fi

# 3. 平台适配
case "${OS_TYPE}" in
    "windows")
        log_info "Building for Windows (MSYS2)..."
        export CXX="g++"
        export CC="gcc"
        export CXXFLAGS="-g -O3 -fpermissive -static-libgcc -static-libstdc++"
        export LDFLAGS="-static-libgcc -static-libstdc++"
        
        # Windows 使用基础配置
        make clean 2>/dev/null || true
        make -j${MAKE_JOBS} portable=1
        ;;
    
    "macos")
        log_info "Building for macOS..."
        export CXX="clang++"
        export CC="clang"
        
        # macOS 检测 CPU 类型
        if sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "Apple"; then
            log_info "Using Apple Silicon (ARM64)"
            export CXXFLAGS="-g -O3 -fpermissive -arch arm64"
        else
            log_info "Using Intel (x86_64)"
            export CXXFLAGS="-g -O3 -fpermissive"
        fi
        
        make clean 2>/dev/null || true
        make -j${MAKE_JOBS}
        ;;
    
    "linux")
        log_info "Building for Linux..."
        
        # 检测 CPU 支持的 SIMD 指令集
        if grep -q "avx512" /proc/cpuinfo 2>/dev/null; then
            log_info "Using AVX512"
            export ARCH="avx512"
        elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
            log_info "Using AVX2"
            export ARCH="avx2"
        elif grep -q "avx" /proc/cpuinfo 2>/dev/null; then
            log_info "Using AVX"
            export ARCH="avx"
        else
            log_info "Using SSE4.2"
            export ARCH="sse42"
        fi
        
        # 静态编译
        export CXXFLAGS="-g -O3 -fpermissive -static-libgcc -static-libstdc++"
        export LDFLAGS="-static-libgcc -static-libstdc++"
        
        make clean 2>/dev/null || true
        make -j${MAKE_JOBS} portable=1 arch=${ARCH}
        ;;
esac

# 4. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"

# bwa-mem2 输出为 bwa-mem2
if [ -f "bwa-mem2${EXE_EXT}" ]; then
    cp -f "bwa-mem2${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
elif [ -f "bwa-mem2" ]; then
    cp -f bwa-mem2 "${INSTALL_PREFIX}/bin/"
fi

# 5. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa-mem2${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa-mem2 installed to ${INSTALL_PREFIX}/bin/"
