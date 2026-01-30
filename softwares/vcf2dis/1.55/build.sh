#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building VCF2Dis in: $(pwd)"

# 3. 设置基础编译变量
CXX="g++"
CXXFLAGS="-O3 -Wall"
LDFLAGS="-lz"
OMP_FLAGS="-fopenmp"

# 4. 平台特定优化
case "${OS_TYPE}" in
    "windows")
        log_info "Optimization for Windows - Static & OpenMP"
        # MinGW 支持 -fopenmp，但需要静态链接相关库
        CXXFLAGS="${CXXFLAGS} -static"
        LDFLAGS="-static-libgcc -static-libstdc++ ${LDFLAGS} -lpthread"
        ;;

    "macos")
        log_info "Optimization for macOS..."
        # macOS 默认编译器不支持 -fopenmp，寻找 Homebrew 的 libomp
        if [ -d "/opt/homebrew/opt/libomp" ]; then
            BP="/opt/homebrew/opt/libomp"
        elif [ -d "/usr/local/opt/libomp" ]; then
            BP="/usr/local/opt/libomp"
        fi

        if [ -n "$BP" ]; then
            log_info "libomp found, enabling multi-threading..."
            CXXFLAGS="${CXXFLAGS} -Xpreprocessor -fopenmp -I${BP}/include"
            LDFLAGS="${LDFLAGS} -L${BP}/lib -lomp"
        else
            log_warn "libomp not found, building single-thread version only."
            OMP_FLAGS=""
        fi
        
        # 处理 macOS zlib
        [ -d "/opt/homebrew/opt/zlib" ] && ZDIR="/opt/homebrew/opt/zlib" || ZDIR="/usr/local/opt/zlib"
        CXXFLAGS="${CXXFLAGS} -I${ZDIR}/include"
        LDFLAGS="-L${ZDIR}/lib ${LDFLAGS}"
        ;;

    "linux")
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
            log_info "Cross-compiling for Linux ARM64..."
            CXX="aarch64-linux-gnu-g++"
            LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu -lz"
        else
            CXXFLAGS="${CXXFLAGS} -static"
            LDFLAGS="-static ${LDFLAGS}"
        fi
        ;;
esac

# 5. 执行编译逻辑 (参考官方 make.sh)
mkdir -p bin
mkdir -p "${INSTALL_PREFIX}/bin"

# --- 编译多线程版本 (multi) ---
if [ -n "$OMP_FLAGS" ]; then
    log_info "Compiling multi-thread version..."
    cp src/Ver/VCF2Dis_multi.cpp src/VCF2Dis_tmp.cpp
    # 注意：我们忽略源码自带的 -L src/zlib，使用系统库
    $CXX $CXXFLAGS $OMP_FLAGS src/VCF2Dis_tmp.cpp $LDFLAGS -o "${INSTALL_PREFIX}/bin/VCF2Dis_multi${EXE_EXT}" || log_warn "Multi-thread build failed."
fi

# --- 编译单线程版本 (single) ---
log_info "Compiling single-thread version..."
cp src/Ver/VCF2Dis_single.cpp src/VCF2Dis_tmp.cpp
$CXX $CXXFLAGS src/VCF2Dis_tmp.cpp $LDFLAGS -o "${INSTALL_PREFIX}/bin/VCF2Dis_single${EXE_EXT}"

# --- 创建默认链接 ---
cd "${INSTALL_PREFIX}/bin"
if [ "$OS_TYPE" == "windows" ]; then
    # Windows 不支持 ln -s，直接复制一份作为默认
    if [ -f "VCF2Dis_multi${EXE_EXT}" ]; then
        cp "VCF2Dis_multi${EXE_EXT}" "VCF2Dis${EXE_EXT}"
    else
        cp "VCF2Dis_single${EXE_EXT}" "VCF2Dis${EXE_EXT}"
    fi
else
    if [ -f "VCF2Dis_multi${EXE_EXT}" ]; then
        ln -sf "VCF2Dis_multi${EXE_EXT}" "VCF2Dis${EXE_EXT}"
    else
        ln -sf "VCF2Dis_single${EXE_EXT}" "VCF2Dis${EXE_EXT}"
    fi
fi

# 6. 验证
log_info "Build finished. Binaries in ${INSTALL_PREFIX}/bin/"
file "VCF2Dis_single${EXE_EXT}" || true
