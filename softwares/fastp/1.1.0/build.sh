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
    pacman -Sy --noconfirm base-devel cmake nasm yasm \
        mingw-w64-x86_64-zlib mingw-w64-x86_64-bzip2 \
        mingw-w64-x86_64-xz mingw-w64-x86_64-libdeflate \
        mingw-w64-x86_64-isa-l git autoconf automake libtool || true
fi

# 4. 安装静态库
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
    export CC="x86_64-w64-mingw32-gcc"
    export CXX="x86_64-w64-mingw32-g++"
    # 简单优化，添加调试信息
    export CFLAGS="-O1 -g"
    export CXXFLAGS="-O1 -g"
    # 不使用静态链接，让系统处理依赖
    export LDFLAGS=""
    export LIBRARY_DIRS="/mingw64/lib"
    export LIBS="-lisal -ldeflate -lbz2 -llzma -lz -lpthread"
fi

# 6. 清理并构建
cd "${SRC_PATH}"
log_info "Building fastp..."

make clean 2>/dev/null || true

if [ "$OS_TYPE" == "windows" ]; then
    # Windows 构建：输出详细编译信息
    log_info "Compiling with: CXX=$CXX CXXFLAGS=$CXXFLAGS"
    make -j${MAKE_JOBS} CXX="$CXX" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" LIBRARY_DIRS="$LIBRARY_DIRS" LIBS="$LIBS" 2>&1 | tee compile.log || true
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
    # 检查编译是否成功
    if [ ! -f "fastp.exe" ]; then
        log_err "fastp.exe not found after build"
        cat compile.log
        exit 1
    fi
    
    cp fastp.exe "${INSTALL_PREFIX}/bin/"
    
    # 复制运行时 DLL
    log_info "Copying runtime DLLs..."
    for dll in libgcc_s_seh-1 libstdc++-6 libdeflate libbz2-2 liblzma-5 libz-1 pthread-2; do
        if [ -f "/mingw64/bin/${dll}.dll" ]; then
            cp "/mingw64/bin/${dll}.dll" "${INSTALL_PREFIX}/bin/" 2>/dev/null && log_info "Copied ${dll}.dll" || true
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
    
    # Windows: 检查依赖
    if [ "$OS_TYPE" == "windows" ]; then
        log_info "Listing binary and DLLs..."
        ls -la "${INSTALL_PREFIX}/bin/"
        
        log_info "Checking DLL dependencies..."
        # 使用 objdump 检查
        if command -v objdump &>/dev/null; then
            objdump -p "$FINAL_BIN" 2>/dev/null | grep -E "DLL Name" || true
        fi
    fi
else
    log_err "Build artifact not found: $FINAL_BIN"
    exit 1
fi
