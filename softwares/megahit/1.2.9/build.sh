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

# 5. Windows 兼容性补丁
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows compatibility patches..."
    
    # 补丁1: 替换 sys/resource.h 为条件编译
    if grep -q '#include <sys/resource.h>' "${SRC_PATH}/src/utils/utils.h" 2>/dev/null; then
        log_info "Patching utils.h for Windows..."
        # 替换 sys/resource.h 相关内容
        if command -v gsed &> /dev/null; then
            gsed -i 's/#include <sys\/resource.h>/#ifdef _WIN32\n#include <windows.h>\nstatic int getrusage(int who, void *rusage) { return 0; }\n#else\n#include <sys\/resource.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
        else
            sed -i '' 's/#include <sys\/resource.h>/#ifdef _WIN32\n#include <windows.h>\nstatic int getrusage(int who, void *rusage) { return 0; }\n#else\n#include <sys\/resource.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h" 2>/dev/null || \
            sed -i 's/#include <sys\/resource.h>/#ifdef _WIN32\n#include <windows.h>\nstatic int getrusage(int who, void *rusage) { return 0; }\n#else\n#include <sys\/resource.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
        fi
    fi
    
    # 补丁2: 替换 sys/time.h
    if grep -q '#include <sys/time.h>' "${SRC_PATH}/src/utils/utils.h" 2>/dev/null; then
        log_info "Patching sys/time.h for Windows..."
        if command -v gsed &> /dev/null; then
            gsed -i 's/#include <sys\/time.h>/#ifndef _WIN32\n#include <sys\/time.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
        else
            sed -i '' 's/#include <sys\/time.h>/#ifndef _WIN32\n#include <sys\/time.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h" 2>/dev/null || \
            sed -i 's/#include <sys\/time.h>/#ifndef _WIN32\n#include <sys\/time.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
        fi
    fi
    
    # 补丁3: unistd.h
    if grep -q '#include <unistd.h>' "${SRC_PATH}/src/utils/utils.h" 2>/dev/null; then
        log_info "Patching unistd.h for Windows..."
        if command -v gsed &> /dev/null; then
            gsed -i 's/#include <unistd.h>/#ifndef _WIN32\n#include <unistd.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
        else
            sed -i '' 's/#include <unistd.h>/#ifndef _WIN32\n#include <unistd.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h" 2>/dev/null || \
            sed -i 's/#include <unistd.h>/#ifndef _WIN32\n#include <unistd.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
        fi
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
    # Windows 不支持 megahit（依赖 POSIX 头文件如 sys/resource.h）
    # 建议：使用 WSL 或跳过 Windows 构建
    log_err "megahit is not supported on Windows (requires POSIX headers like sys/resource.h)"
    log_err "Please build on Linux/macOS or use WSL"
    
    # 尝试构建但不保证成功
    log_warn "Attempting build anyway..."
    
    cmake .. \
        -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 || {
        log_err "Windows build failed as expected. Use Linux/macOS instead."
        exit 1
    }
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
