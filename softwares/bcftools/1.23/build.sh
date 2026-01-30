#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/bcftools/1.23/source.env

# 2. 进入源码
cd "${SRC_PATH}"

# 3. 补全 HTSlib
if [ ! -d "htslib/htscodecs" ]; then
    log_info "HTSlib or htscodecs missing. Fetching sub-components..."
    
    # 下载 HTSlib
    curl -L "${HTSLIB_URL}" -o htslib.tar.gz
    mkdir -p htslib
    tar -zxf htslib.tar.gz -C htslib --strip-components=1
    rm htslib.tar.gz

    # 下载 htscodecs (放入 htslib 内部)
    curl -L "${HTSCODECS_URL}" -o htscodecs.tar.gz
    mkdir -p htslib/htscodecs
    tar -zxf htscodecs.tar.gz -C htslib/htscodecs --strip-components=1
    rm htscodecs.tar.gz
fi

# 4. 路径与工具准备 (针对 macOS)
if [ "$OS_TYPE" == "macos" ]; then
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
fi

# 5. 级联引导构建系统 (Bootstrap)
log_info "Bootstrapping htscodecs -> htslib -> bcftools..."
# 必须按顺序从最底层开始生成 configure
(cd htslib/htscodecs && autoreconf -vfi)
(cd htslib && autoreconf -vfi)
autoreconf -vfi

# 6. 配置编译参数
CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl --enable-configure-htslib"

# 7. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    for pkg in bzip2 zlib xz curl; do
        if [ -d "$BP/opt/$pkg" ]; then
            export CPPFLAGS="$CPPFLAGS -I$BP/opt/$pkg/include"
            export LDFLAGS="$LDFLAGS -L$BP/opt/$pkg/lib"
        fi
    done
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

# 8. 执行编译
log_info "Configuring..."
./configure ${CONF_FLAGS} || { 
    echo "Check htslib/config.log for details"; 
    [ -f htslib/config.log ] && tail -n 50 htslib/config.log; 
    exit 1; 
}

log_info "Building..."
make -j${MAKE_JOBS}
make install

# 9. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Success! Binary format:"
    file "$FINAL_BIN" || true
else
    log_err "Build failed, binary not found."
    exit 1
fi
