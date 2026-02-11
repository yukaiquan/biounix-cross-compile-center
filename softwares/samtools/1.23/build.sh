#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building samtools Release in: $(pwd)"

# 3. 初始化配置参数
# --without-curses: 禁用 tview，解决全平台 curses 报错问题，实现全静态编译
# --disable-libcurl: 禁用网络功能，确保 Windows/Linux 静态单文件兼容性
# --with-htslib=local: 使用本地静态编译的 htslib

# 查找本地 htslib
HTSLIB_PATH="${BUILD_DIR}/htslib-${HTSLIB_VER:-1.23}"

if [ -d "$HTSLIB_PATH" ]; then
    log_info "Using local htslib from: $HTSLIB_PATH"
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --with-htslib=${HTSLIB_PATH} --without-curses"
    # 添加 pkg-config 路径
    export PKG_CONFIG_PATH="${HTSLIB_PATH}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    log_info "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
else
    log_warn "Local htslib not found, using system htslib"
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --without-curses"
fi

# 平台特定配置
if [ "$OS_TYPE" == "macos" ]; then
    CONF_FLAGS="${CONF_FLAGS} --enable-libcurl"
else
    CONF_FLAGS="${CONF_FLAGS} --disable-libcurl"
fi

# 4. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    log_info "Applying macOS Homebrew paths..."
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    export CPPFLAGS="$CPPFLAGS -I$BP/opt/bzip2/include -I$BP/opt/zlib/include -I$BP/opt/xz/include"
    export LDFLAGS="$LDFLAGS -L$BP/opt/bzip2/lib -L$BP/opt/zlib/lib -L$BP/opt/xz/lib"
fi

if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows Static Regex Fix..."
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    # Windows 静态链接需要 Regex 支持 (tre)
    export LIBS="-ltre -lintl -liconv -lws2_32 -lbcrypt -lcrypt32 -lshlwapi -lpsapi -lpthread"
fi

if [ "$OS_TYPE" == "linux" ]; then
    log_info "Applying Linux Static Flags..."
    export LDFLAGS="-static"
    
    # 原生 ARM64 不需要交叉编译
    if [ "${ARCH_TYPE}" == "arm64" ]; then
        log_info "Native ARM64 build"
    # 交叉编译（仅当架构不匹配时）
    elif [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        log_info "Cross-compiling for Linux ARM64..."
        export HOST_ALIAS="aarch64-linux-gnu"
        CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
        export CC="${HOST_ALIAS}-gcc"
        export AR="${HOST_ALIAS}-ar"
        export RANLIB="${HOST_ALIAS}-ranlib"
        export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
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
