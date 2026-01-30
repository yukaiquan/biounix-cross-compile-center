#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/bcftools/1.23/source.env

# 2. 检查并进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid: '$SRC_PATH'"
fi
cd "${SRC_PATH}"

# 3. 准备 HTSlib
if [ ! -d "htslib" ]; then
    log_info "Downloading HTSlib..."
    curl -L "${HTSLIB_URL}" -o htslib.tar.gz
    mkdir -p htslib
    tar -zxf htslib.tar.gz -C htslib --strip-components=1
    rm htslib.tar.gz
fi

# 4. 解决 autoreconf 找不到的问题 (针对 macOS)
if [ "$OS_TYPE" == "macos" ]; then
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
fi

# 5. 引导构建系统
log_info "Bootstrapping with autoreconf..."
(cd htslib && autoreconf -vfi)
autoreconf -vfi

# 6. 核心修复：针对平台配置编译器和库路径
CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl --enable-configure-htslib"

if [ "$OS_TYPE" == "macos" ]; then
    log_info "Configuring paths for macOS Homebrew keg-only libs..."
    # 探测 Homebrew 路径 (Intel/Apple Silicon 不同)
    [ -d "/opt/homebrew" ] && BREW_PREFIX="/opt/homebrew" || BREW_PREFIX="/usr/local"
    
    # 针对 bzip2, zlib, xz, curl 补全路径
    for pkg in bzip2 zlib xz curl; do
        PKG_DIR="${BREW_PREFIX}/opt/${pkg}"
        if [ -d "$PKG_DIR" ]; then
            export CPPFLAGS="$CPPFLAGS -I${PKG_DIR}/include"
            export LDFLAGS="$LDFLAGS -L${PKG_DIR}/lib"
            # 特别针对 bzip2，有时需要增加环境变量
            [ "$pkg" == "bzip2" ] && export BZIP2_PREFIX="${PKG_DIR}"
        fi
    done
    export LDFLAGS="$LDFLAGS -Wl,-headerpad_max_install_names"
fi

if [ "$OS_TYPE" == "windows" ]; then
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    export LIBS="-lws2_32 -lbcrypt -lcrypt32 -lshlwapi -lpsapi -lpthread"
    CONF_FLAGS="${CONF_FLAGS} --disable-plugins"
fi

if [ "$OS_TYPE" == "linux" ]; then
    export LDFLAGS="-static"
    if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        export HOST_ALIAS="aarch64-linux-gnu"
        CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
        export CC="${HOST_ALIAS}-gcc"
        export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
    fi
fi

# 7. 配置、编译、安装
log_info "Running configure..."
./configure ${CONF_FLAGS} || { 
    echo "--- config.log ---"; [ -f config.log ] && tail -n 100 config.log;
    echo "--- htslib/config.log ---"; [ -f htslib/config.log ] && tail -n 100 htslib/config.log;
    log_err "Configure failed."; 
}

log_info "Running make..."
make -j${MAKE_JOBS}
make install

# 8. 产物验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful: $(file $FINAL_BIN)"
else
    log_err "Binary not found!"
    exit 1
fi
