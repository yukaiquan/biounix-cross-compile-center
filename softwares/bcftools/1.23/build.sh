#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/bcftools/1.23/source.env

# 2. 进入源码
cd "${SRC_PATH}"

# 3. 补全 HTSlib 和 htscodecs (手动处理子模块)
if [ ! -d "htslib/htscodecs" ]; then
    log_info "Fetching missing sub-components (HTSlib & htscodecs)..."
    curl -L "${HTSLIB_URL}" -o htslib.tar.gz
    mkdir -p htslib && tar -zxf htslib.tar.gz -C htslib --strip-components=1 && rm htslib.tar.gz

    curl -L "${HTSCODECS_URL}" -o htscodecs.tar.gz
    mkdir -p htslib/htscodecs && tar -zxf htscodecs.tar.gz -C htslib/htscodecs --strip-components=1 && rm htscodecs.tar.gz
fi

# 4. 环境准备 (针对 macOS 和跨平台工具)
if [ "$OS_TYPE" == "macos" ]; then
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    export PATH="$BP/bin:$PATH"
    # 核心修复：让 pkg-config 能找到 Homebrew 的 curl 和 openssl
    export PKG_CONFIG_PATH="$BP/opt/curl/lib/pkgconfig:$BP/opt/zlib/lib/pkgconfig:$BP/opt/xz/lib/pkgconfig:$PKG_CONFIG_PATH"
fi

# 5. 级联引导构建系统 (解决 HTSCODECS_VERSION_TEXT 缺失)
log_info "Bootstrapping build system..."
# 必须先配置 htscodecs 才能生成所需的 version.h
cd htslib/htscodecs
autoreconf -vfi
./configure --disable-shared --prefix="${INSTALL_PREFIX}" || exit 1
cd ../..

cd htslib
autoreconf -vfi
cd ..
autoreconf -vfi

# 6. 初始化配置参数
# 如果在 Linux 上静态编译 libcurl 极度困难，建议增加 --disable-libcurl 选项
# 但我们先尝试通过路径修复来解决
CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl --enable-configure-htslib"

# 7. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    log_info "Applying macOS Homebrew paths..."
    # 显式指向 curl 和 bzip2 路径，解决 "libcurl library not found"
    export CPPFLAGS="$CPPFLAGS -I$BP/opt/curl/include -I$BP/opt/bzip2/include"
    export LDFLAGS="$LDFLAGS -L$BP/opt/curl/lib -L$BP/opt/bzip2/lib"
fi

if [ "$OS_TYPE" == "windows" ]; then
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    # Windows 静态链接 libcurl 需要的一系列系统库
    export LIBS="-lws2_32 -lbcrypt -lcrypt32 -lshlwapi -lpsapi -lpthread -lidn2 -lunistring -liconv"
    CONF_FLAGS="${CONF_FLAGS} --disable-plugins"
fi

if [ "$OS_TYPE" == "linux" ]; then
    # Linux 全静态链接 libcurl 非常复杂 (涉及 openssl, nghttp2, idn2 等)
    # 建议：如果不需要 HTTPS 远程读取，使用 --disable-libcurl 保证 100% 成功
    # 这里我们尝试保留，但如果报错，请手动改为 CONF_FLAGS="${CONF_FLAGS} --disable-libcurl"
    export LDFLAGS="-static"
    
    if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        export HOST_ALIAS="aarch64-linux-gnu"
        CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
        export CC="${HOST_ALIAS}-gcc"
        export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
    fi
fi

# 8. 执行编译
log_info "Running configure with flags: ${CONF_FLAGS}"
./configure ${CONF_FLAGS} || { 
    echo "FAILED: Check htslib/config.log"; 
    [ -f htslib/config.log ] && tail -n 100 htslib/config.log; 
    exit 1; 
}

log_info "Building..."
make -j${MAKE_JOBS}
make install

# 9. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful! Binary format:"
    file "$FINAL_BIN" || true
else
    log_err "Build failed, binary not found."
    exit 1
fi
