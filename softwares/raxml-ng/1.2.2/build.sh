#!/bin/bash
set -e

source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 进入源码目录
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid: '$SRC_PATH'"
fi
cd "${SRC_PATH}"

log_info "Current Source Directory Content:"
ls -F

# 核心：raxml-ng 源码包如果解压出来有多层，确保进入到含有 CMakeLists.txt 的那一层
if [ ! -f "CMakeLists.txt" ] && [ -d "raxml-ng" ]; then
    cd raxml-ng
fi

log_info "Building raxml-ng in: $(pwd)"

# 准备 CMake 参数
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_PTHREADS=ON -DUSE_MPI=OFF -DUSE_GMP=ON"

# 针对 ARM 禁用 x86 特有的指令集优化
if [[ "$ARCH_TYPE" == "arm64" ]]; then
    CMAKE_OPTS="$CMAKE_OPTS -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
fi

case "${OS_TYPE}" in
    "windows")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="MSYS Makefiles"
        ;;
    "macos")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        ;;
    "linux")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles"
        # 交叉编译处理
        if [[ "$ARCH_TYPE" == "arm64" && "$(uname -m)" != "aarch64" ]]; then
            # 这里简单地传递编译器给 CMake
            CMAKE_OPTS="$CMAKE_OPTS -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
        fi
        ;;
esac

# 构建
mkdir -p build && cd build
cmake .. -G "$GENERATOR" $CMAKE_OPTS
make -j${MAKE_JOBS}

# 安装
mkdir -p "${INSTALL_PREFIX}/bin"
# RAxML-NG 的二进制文件通常生成在 build/bin 下
if [ -f "bin/raxml-ng${EXE_EXT}" ]; then
    cp -f bin/raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
else
    # 兜底查找
    find . -name "raxml-ng${EXE_EXT}" -exec cp {} "${INSTALL_PREFIX}/bin/" \;
fi

log_info "RAxML-NG Build Complete."
