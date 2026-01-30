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

# 3. 确保我们在包含顶级 CMakeLists.txt 的目录
if [ ! -f "CMakeLists.txt" ]; then
    log_info "Searching for top-level CMakeLists.txt..."
    TOP_ROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$TOP_ROOT" ] && cd "$TOP_ROOT"
fi
log_info "Final build root: $(pwd)"

# --- 4. 核心修复：针对 Windows 的源码补丁 ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows-specific patches to pll-modules..."
    
    # 修复 1: 将 pllmod_set_error 中的变量名 errno 修改为 pll_errno
    # 否则在 MinGW 下会与系统宏 errno 冲突
    find libs/pll-modules -type f \( -name "*.h" -o -name "*.c" \) -exec sed -i 's/\berrno\b/pll_errno/g' {} +

    # 修复 2: 提高 CMake 最低版本要求，解决 "Compatibility with CMake < 3.5 has been removed"
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[2]./cmake_minimum_required(VERSION 3.5/g' {} +
fi

# 5. 初始化 CMake 参数
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

# 6. 平台适配
case "${OS_TYPE}" in
    "windows")
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

# 7. ARM 指令集修正
if [ "${ARCH_TYPE}" == "arm64" ]; then
    CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
    if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
    fi
fi

# 8. 执行构建
rm -rf build_dir && mkdir build_dir && cd build_dir
log_info "Running CMake..."
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}

log_info "Running Make..."
make -j${MAKE_JOBS}

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
find . -name "raxml-ng${EXE_EXT}" -type f -exec cp -f {} "${INSTALL_PREFIX}/bin/" \;

# 10. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful! format:"
    file "$FINAL_BIN" || true
else
    log_err "raxml-ng binary not found!"
    exit 1
fi
