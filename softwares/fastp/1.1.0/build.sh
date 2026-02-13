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

# 3. 安装编译依赖
log_info "Installing build dependencies..."

if [ "$OS_TYPE" == "linux" ]; then
    # 安装 isa-l (Intel Storage Acceleration Library)
    if [ ! -f "/usr/lib64/liblisal.a" ] && [ ! -f "/usr/lib/liblisal.a" ]; then
        log_info "Installing isa-l..."
        cd /tmp
        rm -rf isa-l
        git clone https://github.com/intel/isa-l.git
        cd isa-l
        ./autogen.sh
        ./configure --prefix=/usr --libdir=/usr/lib64
        make -j${MAKE_JOBS}
        sudo make install
        sudo ldconfig
    else
        log_info "isa-l already installed"
    fi

    # 安装 libdeflate
    if [ ! -f "/usr/lib64/libdeflate.a" ] && [ ! -f "/usr/lib/libdeflate.a" ]; then
        log_info "Installing libdeflate..."
        cd /tmp
        rm -rf libdeflate
        git clone https://github.com/ebiggers/libdeflate.git
        cd libdeflate
        cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=/usr/lib64
        cmake --build build
        sudo cmake --install build
        sudo ldconfig
    else
        log_info "libdeflate already installed"
    fi

    # 设置编译环境变量
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O2 -static -s"
    export CXXFLAGS="-O2 -static -s"
    export LDFLAGS="-static -L/usr/lib64"
    export PKG_CONFIG_PATH="/usr/lib64/pkgconfig:$PKG_CONFIG_PATH"
    export ENABLE_STATIC=1

elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 使用 brew 安装依赖
    log_info "Installing dependencies via brew..."
    brew install libdeflate isa-l || true
    
    # 设置编译环境变量
    export CC="clang"
    export CXX="clang++"
    export CFLAGS="-O2"
    export CXXFLAGS="-O2"
    export LDFLAGS=""
    # 设置库路径
    export LIBDEFLATE_PREFIX=$(brew --prefix libdeflate)
    export ISAL_PREFIX=$(brew --prefix isa-l)
    export LDFLAGS="-L$LIBDEFLATE/lib -L$ISAL/lib"

elif [ "$OS_TYPE" == "windows" ]; then
    export RUSTUP_HOME="/c/Users/runneradmin/.rustup"
    export CARGO_HOME="/c/Users/runneradmin/.cargo"
    export PATH="$CARGO_HOME/bin:$PATH"
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O2 -s"
    export CXXFLAGS="-O2 -s"
fi

# 4. 返回源码目录构建 fastp
cd "${SRC_PATH}"
log_info "Building fastp..."

# 清理旧产物
make clean || true

if [ "$OS_TYPE" == "linux" ]; then
    # Linux 静态编译
    make -j${MAKE_JOBS} CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS"
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 编译
    make -j${MAKE_JOBS}
elif [ "$OS_TYPE" == "windows" ]; then
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
