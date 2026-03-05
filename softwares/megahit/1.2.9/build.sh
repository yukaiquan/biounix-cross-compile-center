#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env

# 2. 进入源码目录
cd "${SRC_PATH}"
log_info "Building megahit in: $(pwd)"

# 3. 初始化 submodules
if [ "$NEEDS_SUBMODULES" = "true" ]; then
    log_info "Initializing submodules..."
    git submodule update --init --recursive
fi

# 4. 修复 CMakeLists.txt 版本要求（如果有 range 语法）
if grep -q "cmake_minimum_required.*\.\.\." "${SRC_PATH}/CMakeLists.txt" 2>/dev/null; then
    log_info "Patching CMakeLists.txt for older CMake..."
    # macOS 使用 gsed，Linux 用 sed
    if command -v gsed &> /dev/null; then
        gsed -i 's/cmake_minimum_required(VERSION 3\.5\.\.\.4\.1)/cmake_minimum_required(VERSION 2.8)/' "${SRC_PATH}/CMakeLists.txt"
    else
        sed -i '' 's/cmake_minimum_required(VERSION 3\.5\.\.\.4\.1)/cmake_minimum_required(VERSION 2.8)/' "${SRC_PATH}/CMakeLists.txt" 2>/dev/null || \
        sed -i 's/cmake_minimum_required(VERSION 3\.5\.\.\.4\.1)/cmake_minimum_required(VERSION 2.8)/' "${SRC_PATH}/CMakeLists.txt"
    fi
fi

# 5. 创建构建目录
cd "${SRC_PATH}"
rm -rf build
mkdir -p build
cd build

# 6. 配置编译选项
if [ "$OS_TYPE" == "linux" ]; then
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O3 -DNDEBUG"
    export CXXFLAGS="-O3 -DNDEBUG -fopenmp"
    export LDFLAGS="-fopenmp -static"
    
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DSTATIC_BUILD=ON \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5

elif [ "$OS_TYPE" == "macos" ]; then
    export CC="clang"
    export CXX="clang++"
    export CFLAGS="-O3 -DNDEBUG"
    export CXXFLAGS="-O3 -DNDEBUG -std=c++11 -fopenmp"
    
    # macOS 不支持静态链接 OpenMP，使用动态链接
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"

elif [ "$OS_TYPE" == "windows" ]; then
    # Windows MSYS2 环境
    # 使用系统默认的编译器 (gcc from mingw)
    cmake .. \
        -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DSTATIC_BUILD=ON \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
fi

# 7. 编译
log_info "Compiling megahit..."
make -j${MAKE_JOBS}

# 8. 安装
log_info "Installing..."
make install

# 9. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/megahit${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN"
    ls -la "$FINAL_BIN"
    
    # 显示版本
    "$FINAL_BIN" --version 2>&1 | head -3 || true
else
    log_err "Build artifact not found: $FINAL_BIN"
    # 尝试其他可能的路径
    ls -la "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
    exit 1
fi
