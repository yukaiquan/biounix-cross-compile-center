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
    # Linux 静态编译依赖
    sudo apt-get update -qq
    sudo apt-get install -y build-essential cmake nasm yasm zlib1g-dev git \
        autoconf automake libtool pkg-config help2man libdeflate-dev || true
    
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 使用 brew
    log_info "Installing dependencies via brew..."
    brew install libdeflate nasm yasm autoconf automake libtool || true
    # 设置 brew bin 路径
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    
elif [ "$OS_TYPE" == "windows" ]; then
    # Windows MSYS2
    export RUSTUP_HOME="/c/Users/runneradmin/.rustup"
    export CARGO_HOME="/c/Users/runneradmin/.cargo"
    export PATH="$CARGO_HOME/bin:$PATH"
    
    # MSYS2 pacman 安装依赖
    pacman -Sy --noconfirm base-devel cmake nasm yasm \
        mingw-w64-x86_64-zlib mingw-w64-x86_64-bzip2 \
        mingw-w64-x86_64-xz mingw-w64-x86_64-libdeflate \
        git autoconf automake libtool || true
fi

# 4. 安装静态库
log_info "Installing static libraries..."

if [ "$OS_TYPE" == "linux" ]; then
    # Linux: 安装 isa-l
    if [ ! -f "/usr/lib64/liblisal.a" ]; then
        log_info "Building isa-l..."
        cd /tmp
        rm -rf isa-l
        git clone --depth 1 https://github.com/intel/isa-l.git
        cd isa-l
        ./autogen.sh
        ./configure --prefix=/usr --libdir=/usr/lib64 --enable-static
        make -j${MAKE_JOBS}
        sudo make install
        sudo ldconfig
    fi
    
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS: 安装 isa-l
    if [ ! -f "/usr/local/lib/liblisal.a" ] && [ ! -f "/opt/homebrew/lib/liblisal.a" ]; then
        log_info "Building isa-l..."
        cd /tmp
        rm -rf isa-l
        git clone --depth 1 https://github.com/intel/isa-l.git
        cd isa-l
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        # macOS 用 autogen.sh 生成 configure
        chmod +x ./autogen.sh
        ./autogen.sh
        ./configure --prefix=/usr/local --enable-static
        make -j${MAKE_JOBS}
        sudo make install
    fi
    
elif [ "$OS_TYPE" == "windows" ]; then
    # Windows: isa-l 交叉编译 - 禁用 igzip 子项目（需要 nasm）
    if [ ! -f "/mingw64/lib/liblisal.a" ]; then
        log_info "Building isa-l for Windows..."
        cd /tmp
        rm -rf isa-l
        git clone --depth 1 https://github.com/intel/isa-l.git
        cd isa-l
        # 交叉编译时禁用 igzip，它需要完整的 nasm 环境
        CC=x86_64-w64-mingw32-gcc ./autogen.sh
        ./configure --prefix=/mingw64 --libdir=/mingw64/lib --host=x86_64-w64-mingw32 --enable-static --disable-igzip
        make -j${MAKE_JOBS}
        make install
    fi
fi

# 5. 设置编译环境变量
log_info "Setting up build environment..."

if [ "$OS_TYPE" == "linux" ]; then
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O2 -static -s"
    export CXXFLAGS="-O2 -static -s"
    export LDFLAGS="-static -L/usr/lib64"
    export LIBRARY_DIRS="/usr/lib64"
    export LIBS="-lisal -ldeflate -lpthread"
    
elif [ "$OS_TYPE" == "macos" ]; then
    export CC="clang"
    export CXX="clang++"
    export CFLAGS="-O2"
    export CXXFLAGS="-O2"
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    LIBDEFLATE_LIB=$(brew --prefix libdeflate)/lib 2>/dev/null || echo "/usr/local/lib"
    ISAL_LIB=$(brew --prefix isa-l)/lib 2>/dev/null || echo "/usr/local/lib"
    export LIBRARY_DIRS="$LIBDEFLATE_LIB $ISAL_LIB"
    export LIBS="-lisal -ldeflate -lpthread"
    
elif [ "$OS_TYPE" == "windows" ]; then
    export CC="x86_64-w64-mingw32-gcc"
    export CXX="x86_64-w64-mingw32-g++"
    export CFLAGS="-O2 -static -s"
    export CXXFLAGS="-O2 -static -s"
    export LDFLAGS="-static -L/mingw64/lib"
    export LIBRARY_DIRS="/mingw64/lib"
    export LIBS="-lisal -ldeflate -lpthread"
fi

# 6. 清理并构建
cd "${SRC_PATH}"
log_info "Building fastp..."

make clean 2>/dev/null || true

if [ "$OS_TYPE" == "linux" ]; then
    make static -j${MAKE_JOBS} CXX="$CXX" CXXFLAGS="$CXXFLAGS" LDFLAGS="-static $LDFLAGS" LIBRARY_DIRS="$LIBRARY_DIRS" LIBS="$LIBS"
elif [ "$OS_TYPE" == "macos" ]; then
    make -j${MAKE_JOBS} CXX="$CXX" CXXFLAGS="$CXXFLAGS" LIBRARY_DIRS="$LIBRARY_DIRS" LIBS="$LIBS"
elif [ "$OS_TYPE" == "windows" ]; then
    make -j${MAKE_JOBS} CXX="$CXX" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" LIBRARY_DIRS="$LIBRARY_DIRS" LIBS="$LIBS"
fi

# 7. 安装产物
log_info "Installing binaries..."
mkdir -p "${INSTALL_PREFIX}/bin"

if [ "$OS_TYPE" == "windows" ]; then
    cp fastp.exe "${INSTALL_PREFIX}/bin/"
else
    cp fastp "${INSTALL_PREFIX}/bin/"
fi

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/fastp${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN"
    ls -la "$FINAL_BIN"
else
    log_err "Build artifact not found: $FINAL_BIN"
    exit 1
fi
