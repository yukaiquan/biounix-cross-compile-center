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

# 4. 创建构建目录
cd "${SRC_PATH}"
rm -rf build
mkdir -p build
cd build

# 5. 配置编译选项
if [ "$OS_TYPE" == "linux" ]; then
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O3 -DNDEBUG"
    export CXXFLAGS="-O3 -DNDEBUG -fopenmp"
    export LDFLAGS="-fopenmp -static"
    
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DSTATIC_BUILD=ON

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
    export CC="clang"
    export CXX="clang++"
    export CMAKE_CXX_FLAGS="-O3 -DNDEBUG -std=c++11"
    export CMAKE_EXE_LINKER_FLAGS="-static"
    
    # Windows MSYS2 环境
    cmake .. \
        -G "MinGW Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DSTATIC_BUILD=ON \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++
fi

# 6. 编译
log_info "Compiling megahit..."
make -j${MAKE_JOBS}

# 7. 安装
log_info "Installing..."
make install

# 8. 验证
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
