#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 目录对准逻辑
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid"
fi
cd "${SRC_PATH}"

# 如果当前目录没有 CMakeLists.txt，尝试进入子目录
if [ ! -f "CMakeLists.txt" ]; then
    log_info "Searching for CMakeLists.txt in subdirectories..."
    REAL_ROOT=$(find . -maxdepth 2 -name "CMakeLists.txt" -print -quit | xargs dirname)
    if [ -n "$REAL_ROOT" ] && [ "$REAL_ROOT" != "." ]; then
        cd "$REAL_ROOT"
    fi
fi
log_info "Final Source Root: $(pwd)"

# 3. 初始化 CMake 参数
# USE_LIBPLL_CMAKE: 使用 CMake 编译依赖库 (非常重要)
# USE_GMP: 开启大数支持，提高数值稳定性
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Configuring for Windows Static Build..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles"
        ;;
    "macos")
        log_info "Configuring for macOS..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        # 寻找 Homebrew 的 GMP
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}"
        ;;
    "linux")
        log_info "Configuring for Linux..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles"
        ;;
esac

# 5. 指令集处理 (针对 ARM 平台必须禁用 SIMD)
if [ "${ARCH_TYPE}" == "arm64" ]; then
    log_info "ARM64 detected. Disabling x86 SIMD (AVX/SSE)..."
    CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
    
    # 交叉编译处理
    if [ "${OS_TYPE}" == "linux" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        log_info "Setting up cross-compiler for ARM64..."
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
    fi
fi

# 6. 执行构建
rm -rf build_dir && mkdir build_dir && cd build_dir
log_info "Running CMake: cmake .. -G \"$GENERATOR\" $CMAKE_OPTS"
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}

log_info "Building raxml-ng..."
make -j${MAKE_JOBS}

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# raxml-ng 的二进制文件可能在 build/bin 或 build/ 直接生成
if [ -f "bin/raxml-ng${EXE_EXT}" ]; then
    cp -f bin/raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
elif [ -f "raxml-ng${EXE_EXT}" ]; then
    cp -f raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
else
    # 暴力搜寻二进制
    find . -maxdepth 3 -name "raxml-ng${EXE_EXT}" -type f -exec cp -f {} "${INSTALL_PREFIX}/bin/" \;
fi

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build Successful!"
    file "$FINAL_BIN" || true
else
    log_err "raxml-ng binary not found. Listing build directory:"
    ls -R
    exit 1
fi
