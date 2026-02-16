#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building fastp in: $(pwd)"

# 3. 安装编译依赖
log_info "Installing build dependencies..."

if [ "$OS_TYPE" == "linux" ]; then
    sudo apt-get update -qq
    sudo apt-get install -y build-essential cmake nasm yasm zlib1g-dev git \
        autoconf automake libtool pkg-config help2man libdeflate-dev || true
    
elif [ "$OS_TYPE" == "macos" ]; then
    brew install libdeflate nasm yasm autoconf automake libtool || true
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    
elif [ "$OS_TYPE" == "windows" ]; then
    export RUSTUP_HOME="/c/Users/runneradmin/.rustup"
    export CARGO_HOME="/c/Users/runneradmin/.cargo"
    export PATH="$CARGO_HOME/bin:$PATH"
    
    # MSYS2 包（clang 版本，兼容性更好）
    pacman -Sy --noconfirm \
        mingw-w64-x86_64-clang \
        mingw-w64-x86_64-cmake \
        mingw-w64-x86_64-nasm \
        mingw-w64-x86_64-yasm \
        mingw-w64-x86_64-zlib \
        mingw-w64-x86_64-bzip2 \
        mingw-w64-x86_64-xz \
        mingw-w64-x86_64-libdeflate \
        mingw-w64-x86_64-isa-l \
        git autoconf automake libtool || true
    
    # 切换到 clang 工具链
    export CC="clang"
    export CXX="clang++"
    export AR="llvm-ar"
    export RANLIB="llvm-ranlib"
    export NM="llvm-nm"
fi

# 4. 安装 isa-l 静态库
if [ "$OS_TYPE" == "linux" ]; then
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
    if [ ! -f "/usr/local/lib/liblisal.a" ] && [ ! -f "/opt/homebrew/lib/liblisal.a" ]; then
        log_info "Building isa-l..."
        cd /tmp
        rm -rf isa-l
        git clone --depth 1 https://github.com/intel/isa-l.git
        cd isa-l
        chmod +x ./autogen.sh
        ./autogen.sh
        ./configure --prefix=/usr/local --enable-static
        make -j${MAKE_JOBS}
        sudo make install
    fi
elif [ "$OS_TYPE" == "windows" ]; then
    # clang 自带 LLVM，不需要 isa-l 静态库
    log_info "Using system isa-l from MSYS2..."
fi

# 5. 设置编译环境
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
    export CXXFLAGS="-O2 -std=c++11 -stdlib=libc++"
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    LIBDEFLATE_LIB=$(brew --prefix libdeflate)/lib 2>/dev/null || echo "/usr/local/lib"
    ISAL_LIB=$(brew --prefix isa-l)/lib 2>/dev/null || echo "/usr/local/lib"
    export LIBRARY_DIRS="$LIBDEFLATE_LIB $ISAL_LIB"
    export LIBS="-lisal -ldeflate -lpthread"
elif [ "$OS_TYPE" == "windows" ]; then
    # Windows + clang: 使用 MSYS2 运行时
    export CFLAGS="-O2 -static"
    export CXXFLAGS="-O2 -std=c++11"
    export LDFLAGS="-static"
    export LIBRARY_DIRS="/mingw64/lib"
    export LIBS="-lisal -ldeflate -lbz2 -llzma -lz -lpthread"
    
    # 重要：使用 mingw 运行时而不是 ucrt
    export CHOST="x86_64-w64-mingw32"
fi

# 6. 清理并构建
cd "${SRC_PATH}"
log_info "Building fastp..."

make clean 2>/dev/null || true

if [ "$OS_TYPE" == "windows" ]; then
    # Windows 构建
    log_info "Using CC=$CC CXX=$CXX"
    make -j${MAKE_JOBS} 2>&1 | tee build.log || {
        log_err "Build failed"
        cat build.log
        exit 1
    }
else
    if [ "$OS_TYPE" == "linux" ]; then
        make static -j${MAKE_JOBS} CXX="$CXX" CXXFLAGS="$CXXFLAGS" LDFLAGS="-static $LDFLAGS" LIBRARY_DIRS="$LIBRARY_DIRS" LIBS="$LIBS"
    else
        make -j${MAKE_JOBS} CXX="$CXX" CXXFLAGS="$CXXFLAGS" LIBRARY_DIRS="$LIBRARY_DIRS" LIBS="$LIBS"
    fi
fi

# 7. 安装产物
log_info "Installing binaries..."
mkdir -p "${INSTALL_PREFIX}/bin"

if [ "$OS_TYPE" == "windows" ]; then
    if [ ! -f "fastp.exe" ]; then
        log_err "fastp.exe not found"
        exit 1
    fi
    
    cp fastp.exe "${INSTALL_PREFIX}/bin/"
    
    # 复制必要 DLL
    log_info "Copying runtime DLLs..."
    for dll in libclang-rt.builtins libdeflate libbz2-2 liblzma-5 libz-1; do
        dllpath="/mingw64/bin/${dll}.dll"
        if [ -f "$dllpath" ]; then
            cp "$dllpath" "${INSTALL_PREFIX}/bin/" 2>/dev/null && log_info "Copied ${dll}.dll" || true
        fi
    done
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
