#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building samtools Release in: $(pwd)"

# 3. 初始化配置参数 (Release 包不需要 autoreconf)
# Linux 和 Windows: 禁用 libcurl 以实现 100% 兼容的静态单文件
if [ "$OS_TYPE" == "macos" ]; then
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl"
else
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --disable-libcurl"
fi

# 4. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    log_info "Applying macOS Homebrew paths..."
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    # 显式包含 ncurses 路径
    export CPPFLAGS="$CPPFLAGS -I$BP/opt/ncurses/include -I$BP/opt/bzip2/include -I$BP/opt/zlib/include -I$BP/opt/xz/include"
    export LDFLAGS="$LDFLAGS -L$BP/opt/ncurses/lib -L$BP/opt/bzip2/lib -L$BP/opt/zlib/lib -L$BP/opt/xz/lib"
fi

if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows Static Fix (Regex & Ncurses)..."
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    # Windows 静态链接需要：Regex(tre), 字符终端(ncurses), 国际化(intl), 以及系统网络/基础库
    export LIBS="-lncurses -ltre -lintl -liconv -lws2_32 -lbcrypt -lcrypt32 -lshlwapi -lpsapi -lpthread"
fi

if [ "$OS_TYPE" == "linux" ]; then
    export LDFLAGS="-static"
    # 静态链接 ncurses 往往需要补充 tinfo
    export LIBS="-ltinfo -lpthread"
    
    if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        log_info "Cross-compiling for Linux ARM64..."
        export HOST_ALIAS="aarch64-linux-gnu"
        CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
        export CC="${HOST_ALIAS}-gcc"
        export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
        # 交叉编译环境下的库通常已经处理好依赖，只需指定静态标志
    fi
fi

# 5. 执行配置
log_info "Configuring with: ${CONF_FLAGS}"
./configure ${CONF_FLAGS} || { [ -f config.log ] && tail -n 50 config.log; exit 1; }

# 6. 编译与安装
log_info "Making..."
make -j${MAKE_JOBS}
make install

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/samtools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi
