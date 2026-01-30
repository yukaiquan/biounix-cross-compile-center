#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bcftools Release in: $(pwd)"

# 3. 初始化配置参数 (注意：Release 包不需要 autoreconf)
# 核心改动：Linux 和 Windows 都要禁用插件以配合静态编译
if [ "$OS_TYPE" == "macos" ]; then
    # macOS 不支持全静态，可以保留插件和 libcurl
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl"
else
    # Linux 和 Windows: 禁用 libcurl 和 plugins 以实现全静态
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --disable-libcurl --disable-plugins"
fi

# 4. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    export CPPFLAGS="$CPPFLAGS -I$BP/opt/bzip2/include -I$BP/opt/zlib/include -I$BP/opt/xz/include"
    export LDFLAGS="$LDFLAGS -L$BP/opt/bzip2/lib -L$BP/opt/zlib/lib -L$BP/opt/xz/lib"
fi

if [ "$OS_TYPE" == "windows" ]; then
    # Windows 静态编译标志
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    # 显式链接 Windows 系统库
    export LIBS="-lws2_32 -lbcrypt -lcrypt32 -lshlwapi -lpsapi -lpthread"
fi

if [ "$OS_TYPE" == "linux" ]; then
    # Linux 全静态编译标志
    export LDFLAGS="-static"
    
    # 如果是交叉编译 ARM64
    if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        log_info "Cross-compiling for Linux ARM64..."
        export HOST_ALIAS="aarch64-linux-gnu"
        CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
        export CC="${HOST_ALIAS}-gcc"
        export AR="${HOST_ALIAS}-ar"
        export RANLIB="${HOST_ALIAS}-ranlib"
        export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
    fi
fi

# 5. 执行配置 (Release 包内置了 configure)
log_info "Configuring with: ${CONF_FLAGS}"
./configure ${CONF_FLAGS} || { 
    echo "--- config.log tail ---"; 
    [ -f config.log ] && tail -n 50 config.log; 
    exit 1; 
}

# 6. 编译与安装
log_info "Making..."
# 强制只编译主程序，不编译插件
make -j${MAKE_JOBS} bcftools
make install

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful! Binary format:"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi
