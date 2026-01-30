#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码目录
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH is invalid: '$SRC_PATH'"
fi
cd "${SRC_PATH}"
log_info "Build start in: $(pwd)"

# 3. 准备 CMake 参数
# raxml-ng 的 STATIC_BUILD 选项在 Linux/Windows 上非常有用
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_PTHREADS=ON -DUSE_MPI=OFF -DUSE_GMP=ON"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Configuring for Windows..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        # MSYS2 下必须指定 Generator，否则可能误用 MSVC
        GENERATOR="MSYS Makefiles"
        ;;

    "macos")
        log_info "Configuring for macOS..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        # 帮助 CMake 找到 Homebrew 的库 (GMP, TBB)
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}"
        ;;

    "linux")
        log_info "Configuring for Linux..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles"

        # 如果是 ARM64，禁用 x86 特有的指令集优化 (AVX/SSE)
        if [ "${ARCH_TYPE}" == "arm64" ]; then
            log_info "Disabling x86 SIMD for ARM64 build"
            CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
            
            # 交叉编译处理
            if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
                CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
            fi
        fi
        ;;
esac

# 5. 执行构建
mkdir -p build_dir && cd build_dir

log_info "Running CMake..."
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}

log_info "Running Make..."
make -j${MAKE_JOBS}

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# raxml-ng 可能会把产物放在 bin/ 或当前 build 目录下
if [ -f "bin/raxml-ng${EXE_EXT}" ]; then
    cp -f bin/raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
elif [ -f "raxml-ng${EXE_EXT}" ]; then
    cp -f raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
else
    # 暴力搜索
    find . -maxdepth 3 -name "raxml-ng${EXE_EXT}" -exec cp {} "${INSTALL_PREFIX}/bin/" \;
fi

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful: $FINAL_BIN"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found!"
    exit 1
fi
