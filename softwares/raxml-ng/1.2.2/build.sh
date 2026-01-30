#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码目录
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH is invalid"
fi
cd "${SRC_PATH}"

# 3. 精准定位 CMakeLists.txt 所在的目录
if [ ! -f "CMakeLists.txt" ]; then
    log_info "Locating real CMake root..."
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi
log_info "Final build root: $(pwd)"

# --- 4. 终极源码补丁 (针对 Windows/MinGW 15+) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying deep patches for Windows/GCC15..."

    # 修复 A: 递归替换所有子模块中的 errno 变量名
    # 范围扩大到 libs 下的所有文件，确保 libpll, pll-modules, terraphast 全部覆盖
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) \
        -exec sed -i 's/\berrno\b/pll_errno/g' {} +

    # 修复 B: 强制提升所有 CMakeLists.txt 的版本要求
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +

    # 修复 C: 屏蔽 GCC 15 过于严格的警告 (防止 strncpy 警告转错误)
    export CXXFLAGS="$CXXFLAGS -Wno-error=stringop-truncation -Wno-error=int-conversion"
    export CFLAGS="$CFLAGS -Wno-error=stringop-truncation -Wno-error=int-conversion"
fi

# 5. 初始化 CMake 参数
# 加入 -DCMAKE_POLICY_DEFAULT_CMP0091=NEW 帮助处理静态运行时
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

case "${OS_TYPE}" in
    "windows")
        log_info "Setting Windows options..."
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

# 6. ARM 适配
if [ "${ARCH_TYPE}" == "arm64" ]; then
    log_info "ARM64: Disabling AVX/SSE..."
    CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
    if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
    fi
fi

# 7. 执行构建
rm -rf build_dir && mkdir build_dir && cd build_dir
log_info "Running CMake..."
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}

log_info "Running Make..."
# 如果失败，尝试不使用并行编译以便观察具体报错
make -j${MAKE_JOBS} || make

# 8. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
find . -name "raxml-ng${EXE_EXT}" -type f -exec cp -f {} "${INSTALL_PREFIX}/bin/" \;

# 9. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "RAxML-NG build successful!"
    file "$FINAL_BIN" || true
else
    log_err "RAxML-NG binary not found!"
    exit 1
fi
