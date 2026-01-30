#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 检查并进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH is invalid"
fi
cd "${SRC_PATH}"

# 再次确认当前目录有 CMakeLists.txt
if [ ! -f "CMakeLists.txt" ]; then
    log_info "Re-locating CMakeLists.txt..."
    CMAKEROOT=$(find . -maxdepth 2 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi
log_info "Final build root: $(pwd)"

# 3. 初始化 CMake 参数
# 特效药：-DCMAKE_POLICY_VERSION_MINIMUM=3.5 解决旧版 submodules 不兼容问题
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

# 4. 平台适配
case "${OS_TYPE}" in
    "windows")
        log_info "Configuring for Windows Static Build..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles"
        ;;
    "macos")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}"
        ;;
    "linux")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles"
        ;;
esac

# 5. ARM 指令集修正
if [ "${ARCH_TYPE}" == "arm64" ]; then
    CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
    if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
    fi
fi

# 6. 执行构建
rm -rf build_dir && mkdir build_dir && cd build_dir
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}
make -j${MAKE_JOBS}

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# raxml-ng 的产物可能在 build_dir/ 或 build_dir/bin 下
find . -name "raxml-ng${EXE_EXT}" -type f -exec cp -f {} "${INSTALL_PREFIX}/bin/" \;

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Success!"
    file "$FINAL_BIN" || true
else
    log_err "raxml-ng binary not found!"
    exit 1
fi
