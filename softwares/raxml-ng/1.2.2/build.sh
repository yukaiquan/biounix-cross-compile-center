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

# 3. 精准定位 CMake 根目录
if [ ! -f "CMakeLists.txt" ]; then
    log_info "Locating real CMake root..."
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi
log_info "Final build root: $(pwd)"

# --- 4. 源码深度手术 (针对 Windows/GCC15 的终极补丁) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying deep compatibility patches for Windows/GCC15..."

    # 修复 A: 解决 pll_utree_parse 和 pll_rtree_parse 的函数原型冲突
    # 将旧式的 extern int xxx(); 修改为带参数的正确原型
    find libs -name "parse_utree.y" -exec sed -i 's/extern int pll_utree_parse();/struct pll_unode_s; int pll_utree_parse(struct pll_unode_s * tree);/g' {} +
    find libs -name "parse_rtree.y" -exec sed -i 's/extern int pll_rtree_parse();/struct pll_rnode_s; int pll_rtree_parse(struct pll_rnode_s * tree);/g' {} +

    # 修复 B: 解决 Bison 的 %error-verbose 过时警告转错误问题
    find libs -name "*.y" -exec sed -i 's/%error-verbose/%define parse.error verbose/g' {} +

    # 修复 C: 解决子模块中的 errno 变量名冲突 (上一步的加固)
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) \
        -exec sed -i 's/\berrno\b/pll_errno/g' {} +

    # 修复 D: 强制提升所有 CMakeLists.txt 的版本
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +

    # 修复 E: 开启编译器“宽容模式”，忽略 C 语言标准不匹配导致的非致命错误
    # -fpermissive: 宽容处理不规范代码
    # -Wno-int-conversion: 忽略指针/整数转换警告
    export CXXFLAGS="$CXXFLAGS -fpermissive -Wno-error=int-conversion -Wno-error=stringop-truncation"
    export CFLAGS="$CFLAGS -Wno-int-conversion -Wno-error=int-conversion -Wno-error=stringop-truncation"
fi

# 5. 初始化 CMake 参数
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

case "${OS_TYPE}" in
    "windows")
        log_info "Setting Windows options..."
        # 强制静态编译
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

# 6. ARM 适配 (保持不变)
if [ "${ARCH_TYPE}" == "arm64" ]; then
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
# 使用单线程编译以获得清晰的错误输出，如果失败则停止
make -j${MAKE_JOBS} || make

# 8. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
find . -name "raxml-ng${EXE_EXT}" -type f -exec cp -f {} "${INSTALL_PREFIX}/bin/" \;

# 9. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "RAxML-NG build SUCCESSFUL!"
    file "$FINAL_BIN" || true
else
    log_err "RAxML-NG binary not found!"
    exit 1
fi
