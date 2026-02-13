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
    # 安装基础依赖
    sudo apt-get update -qq
    sudo apt-get install -y build-essential cmake nasm yasm zlib1g-dev git \
        autoconf automake libtool pkg-config help2man libdeflate-dev || true
    
    # 安装 isa-l (Intel Storage Acceleration Library)
    if [ ! -f "/usr/lib64/liblisal.a" ]; then
        log_info "Installing isa-l..."
        cd /tmp
        rm -rf isa-l
        git clone https://github.com/intel/isa-l.git --depth 1
        cd isa-l
        ./autogen.sh
        ./configure --prefix=/usr --libdir=/usr/lib64 --enable-static
        make -j${MAKE_JOBS}
        sudo make install
        sudo ldconfig
    else
        log_info "isa-l already installed"
    fi

    # 设置编译环境变量
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O2 -static -s"
    export CXXFLAGS="-O2 -static -s"
    export LDFLAGS="-static -L/usr/lib64"
    export LIBRARY_DIRS="/usr/lib64"

elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 安装依赖
    log_info "Installing dependencies via brew..."
    brew install libdeflate nasm yasm autoconf automake libtool || true
    
    # 设置 brew bin 路径
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    
    # isa-l 在 brew 中可能不存在，从源码编译
    if [ ! -f "/usr/local/lib/liblisal.a" ] && [ ! -f "/opt/homebrew/lib/liblisal.a" ]; then
        log_info "Installing isa-l from source..."
        cd /tmp
        rm -rf isa-l
        git clone https://github.com/intel/isa-l.git --depth 1
        cd isa-l
        aclocal
        libtoolize
        autoconf
        ./configure --prefix=/usr/local --enable-static
        make -j${MAKE_JOBS}
        sudo make install
    else
        log_info "isa-l already installed"
    fi
    
    # 设置编译环境变量
    export CC="clang"
    export CXX="clang++"
    export CFLAGS="-O2"
    export CXXFLAGS="-O2"
    # 查找库路径
    LIBDEFLATE_LIB=$(brew --prefix libdeflate)/lib 2>/dev/null || echo "/usr/local/lib"
    ISAL_LIB=$(brew --prefix isa-l)/lib 2>/dev/null || echo "/usr/local/lib"
    export LIBRARY_DIRS="$LIBDEFLATE_LIB $ISAL_LIB"

elif [ "$OS_TYPE" == "windows" ]; then
    # Windows MSYS2 安装依赖
    export RUSTUP_HOME="/c/Users/runneradmin/.rustup"
    export CARGO_HOME="/c/Users/runneradmin/.cargo"
    export PATH="$CARGO_HOME/bin:$PATH"
    
    # 使用 pacman 安装基础依赖
    pacman -Sy --noconfirm base-devel cmake nasm yasm mingw-w64-x86_64-zlib \
        git autoconf automake libtool || true
    
    # 安装 isa-l (需要 MinGW 版本)
    if [ ! -f "/mingw64/lib/liblisal.a" ]; then
        log_info "Installing isa-l..."
        cd /tmp
        rm -rf isa-l
        git clone https://github.com/intel/isa-l.git --depth 1
        cd isa-l
        CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ ./autogen.sh
        ./configure --prefix=/mingw64 --libdir=/mingw64/lib --host=x86_64-w64-mingw32 --enable-static
        make -j${MAKE_JOBS}
        make install
    else
        log_info "isa-l already installed"
    fi
    
    # 安装 libdeflate (MinGW 版本)
    if [ ! -f "/mingw64/lib/libdeflate.a" ]; then
        log_info "Installing libdeflate..."
        cd /tmp
        rm -rf libdeflate
        git clone https://github.com/ebiggers/libdeflate.git --depth 1
        cd libdeflate
        cmake -B build \
            -DCMAKE_INSTALL_PREFIX=/mingw64 \
            -DCMAKE_INSTALL_LIBDIR=/mingw64/lib \
            -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
            -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
            -DBUILD_SHARED_LIBS=OFF
        cmake --build build
        cmake --install build
    else
        log_info "libdeflate already installed"
    fi
    
    # 设置编译环境变量
    export CC="x86_64-w64-mingw32-gcc"
    export CXX="x86_64-w64-mingw32-g++"
    export CFLAGS="-O2"
    export CXXFLAGS="-O2"
    export LIBRARY_DIRS="/mingw64/lib"
fi

# 4. 返回源码目录构建 fastp
cd "${SRC_PATH}"
log_info "Building fastp..."

# 清理旧产物
make clean || true

if [ "$OS_TYPE" == "linux" ]; then
    # Linux 静态编译
    make static -j${MAKE_JOBS}
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 编译 (动态链接，静态链接在 macOS 很复杂)
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
