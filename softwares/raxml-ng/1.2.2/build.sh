#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid: '$SRC_PATH'"
fi
cd "${SRC_PATH}"
log_info "Building raxml-ng in: $(pwd)"

# 3. 准备 CMake 参数
# 默认开启 PTHREADS，禁用 MPI (MPI 静态编译极其复杂)
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_PTHREADS=ON -DUSE_MPI=OFF -DUSE_GMP=ON"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Configuring for Windows (MSYS2)..."
        # Windows 下强制静态编译
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        # 指定使用 MinGW Makefiles
        GENERATOR="MSYS Makefiles"
        ;;

    "macos")
        log_info "Configuring for macOS..."
        # Mac 不支持真正的全静态链接
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        
        # 处理 Homebrew 路径 (针对 GMP 等库)
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}"
        ;;

    "linux")
        log_info "Configuring for Linux..."
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles"

        # 如果是 ARM64，必须禁用 x86 SIMD 优化，否则会报非法指令错误
        if [ "${ARCH_TYPE}" == "arm64" ]; then
            log_info "ARM64 detected: Disabling x86 SIMD optimizations..."
            CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
            
            # 如果是交叉编译
            if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
                export CC="aarch64-linux-gnu-gcc"
                export CXX="aarch64-linux-gnu-g++"
                # 注意：交叉编译 CMake 需要 Toolchain 文件，这里简化处理，
                # 假设系统已经配好了环境变量
            fi
        fi
        ;;
esac

# 5. 执行 CMake 构建
mkdir -p build_dir && cd build_dir

log_info "Running CMake with options: ${CMAKE_OPTS}"
cmake -G "${GENERATOR:-Unix Makefiles}" .. ${CMAKE_OPTS}

log_info "Starting compilation..."
make -j${MAKE_JOBS}

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"

# raxml-ng 编译出来的二进制文件在 bin/ 目录下（源码根目录的 bin）
if [ -f "bin/raxml-ng${EXE_EXT}" ]; then
    cp -f bin/raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
elif [ -f "src/raxml-ng${EXE_EXT}" ]; then
    cp -f src/raxml-ng${EXE_EXT} "${INSTALL_PREFIX}/bin/"
else
    # 有些版本会直接在 build 目录下
    find . -maxdepth 2 -name "raxml-ng${EXE_EXT}" -exec cp {} "${INSTALL_PREFIX}/bin/" \;
fi

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found! Build failed."
    exit 1
fi
