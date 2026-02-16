#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid"
fi
cd "${SRC_PATH}"

# 3. 定位真实根目录
if [ ! -f "CMakeLists.txt" ]; then
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi

# 4. Windows 特殊处理
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows compatibility patches..."
    
    # 修复 sysutil.cpp 中的 cpuid 调用
    if [ -f "src/util/sysutil.cpp" ]; then
        sed -i 's/__cpuid(/raxml_cpuid(/g' src/util/sysutil.cpp
        sed -i 's/u_int32_t/uint32_t/g' src/util/sysutil.cpp
    fi
fi

# 5. CMake 编译参数
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release"
CMAKE_OPTS="${CMAKE_OPTS} -DUSE_LIBPLL_CMAKE=ON"
CMAKE_OPTS="${CMAKE_OPTS} -DUSE_GMP=ON -DUSE_PTHREADS=ON"
# CMake 版本策略，避免兼容性错误
CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

case "${OS_TYPE}" in
    "windows")
        # Windows: 动态编译，禁用 SIMD
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF"
        CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_PLLMOD_SIMD=OFF"
        # Windows 不要静态链接 C++ 运行时
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        # 线程栈大小
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_EXE_LINKER_FLAGS=-Wl,--stack,16777216"
        GENERATOR="MSYS Makefiles"
        ;;
    "linux")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles"
        ;;
    "macos")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        ;;
esac

# 6. 构建
rm -rf build_dir && mkdir build_dir && cd build_dir
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}
make -j${MAKE_JOBS} || make

# 7. 整理
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find . -name "raxml-ng*${EXE_EXT}" -type f | grep -v "test" | head -n 1)
if [ -n "$FOUND_BIN" ]; then
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
    log_info "Build successful!"
else
    log_err "raxml-ng binary not found"
    exit 1
fi
