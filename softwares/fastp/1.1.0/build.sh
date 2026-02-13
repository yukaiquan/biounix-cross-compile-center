#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building fastp in: $(pwd)"
ls -la

# 3. 设置编译环境
log_info "Setting up build environment..."

if [ "$OS_TYPE" == "linux" ]; then
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O2 -static -s"
    export CXXFLAGS="-O2 -static -s"
    export LDFLAGS="-static"
    export ENABLE_STATIC=1
elif [ "$OS_TYPE" == "macos" ]; then
    export CC="clang"
    export CXX="clang++"
    # macOS 不支持完全静态链接，使用动态链接
    export CFLAGS="-O2 -s"
    export CXXFLAGS="-O2 -s"
    export LDFLAGS=""
elif [ "$OS_TYPE" == "windows" ]; then
    export RUSTUP_HOME="/c/Users/runneradmin/.rustup"
    export CARGO_HOME="/c/Users/runneradmin/.cargo"
    export PATH="$CARGO_HOME/bin:$PATH"
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O2 -s"
    export CXXFLAGS="-O2 -s"
fi

# 4. 构建 fastp
log_info "Building fastp..."

if [ "$OS_TYPE" == "linux" ]; then
    # Linux 静态编译
    make -j${MAKE_JOBS} CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS"
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 编译
    make -j${MAKE_JOBS}
elif [ "$OS_TYPE" == "windows" ]; then
    # Windows 编译 (MinGW)
    make -j${MAKE_JOBS}
fi

# 5. 安装产物
log_info "Installing binaries..."
mkdir -p "${INSTALL_PREFIX}/bin"

if [ "$OS_TYPE" == "windows" ]; then
    cp fastp.exe "${INSTALL_PREFIX}/bin/"
else
    cp fastp "${INSTALL_PREFIX}/bin/"
fi

# 6. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/fastp${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    log_info "Binary info:"
    file "$FINAL_BIN"
    ls -la "$FINAL_BIN"
else
    log_err "Build artifact not found: $FINAL_BIN"
    exit 1
fi
