#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码目录并处理可能的嵌套
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH is invalid: '$SRC_PATH'"
fi
cd "${SRC_PATH}"

# 核心修复：raxml-ng 的官方 source.zip 解压后通常是 raxml-ng_v1.2.2_source/raxml-ng/...
# 我们需要确保当前目录下有 CMakeLists.txt
if [ ! -f "CMakeLists.txt" ]; then
    log_info "CMakeLists.txt not found in root, searching in subdirectories..."
    # 查找包含 CMakeLists.txt 的深度为1的子目录
    SUB_CMAKE=$(find . -maxdepth 2 -name "CMakeLists.txt" -print -quit | xargs dirname)
    if [ -n "$SUB_CMAKE" ] && [ "$SUB_CMAKE" != "." ]; then
        cd "$SUB_CMAKE"
        log_info "Moved to source root: $(pwd)"
    fi
fi

log_info "Build start in: $(pwd)"

# 3. 准备基础 CMake 参数
# STATIC_BUILD: raxml-ng 内置支持，会尝试静态链接 libpll 和 gmp
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_PTHREADS=ON -DUSE_MPI=OFF -DUSE_GMP=ON"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Configuring for Windows..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        # 强制指定编译器，防止 CMake 找不到 MinGW
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles"
        ;;

    "macos")
        log_info "Configuring for macOS..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        # 帮助 CMake 找到 Homebrew 的库
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}"
        # macOS 即使不开启 SIMD，CMake 也会检测，通常 M1/M2 选默认即可
        ;;

    "linux")
        log_info "Configuring for Linux..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles"

        # 如果是 ARM64，禁用 x86 特有的 SIMD (AVX/SSE) 优化，否则编译报错
        if [ "${ARCH_TYPE}" == "arm64" ]; then
            log_info "Disabling x86 SIMD for ARM64 build"
            CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
            
            # 交叉编译处理
            if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
                log_info "Setting up Cross-Compiler for ARM64"
                CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
            fi
        fi
        ;;
esac

# 5. 执行构建
mkdir -p build_dir && cd build_dir

log_info "Running CMake..."
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}

log_info "Running Make (this may take a while)..."
make -j${MAKE_JOBS}

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"

# raxml-ng 的二进制文件生成位置比较多变
# 尝试从 build/bin 拷贝，如果不行则全量搜索
if [ -f "bin/raxml-ng${EXE_EXT}" ]; then
    cp -f bin/raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
elif [ -f "raxml-ng${EXE_EXT}" ]; then
    cp -f raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
else
    log_info "Searching for raxml-ng binary..."
    find . -maxdepth 3 -name "raxml-ng${EXE_EXT}" -exec cp {} "${INSTALL_PREFIX}/bin/" \;
fi

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful! Binary location: $FINAL_BIN"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found! Build failed."
    exit 1
fi
