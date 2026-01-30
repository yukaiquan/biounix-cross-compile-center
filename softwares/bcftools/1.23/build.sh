#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bcftools Release in: $(pwd)"

# 3. 初始化配置参数 (Release 包自带 configure，不需要 autoreconf)
# Linux/Windows 为了实现“绿色版”全静态编译，我们主动禁用 libcurl
if [ "$OS_TYPE" == "macos" ]; then
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl"
else
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --disable-libcurl"
fi

# 4. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    export CPPFLAGS="$CPPFLAGS -I$BP/opt/bzip2/include -I$BP/opt/zlib/include -I$BP/opt/xz/include"
    export LDFLAGS="$LDFLAGS -L$BP/opt/bzip2/lib -L$BP/opt/zlib/lib -L$BP/opt/xz/lib"
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

# 5. 执行编译
log_info "Configuring..."
./configure ${CONF_FLAGS} || { [ -f config.log ] && tail -n 50 config.log; exit 1; }

log_info "Making..."
make -j${MAKE_JOBS}
make install

# 6. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found!"
    exit 1
fi
