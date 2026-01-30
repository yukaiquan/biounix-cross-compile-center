#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bcftools Release in: $(pwd)"

# 3. 初始化配置参数 (Release 包不需要 autoreconf)
# 强制禁用 plugins 和 libcurl 以确保静态编译的纯净和成功率
if [ "$OS_TYPE" == "macos" ]; then
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl"
else
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --disable-libcurl --disable-plugins"
fi

# 4. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    export CPPFLAGS="$CPPFLAGS -I$BP/opt/bzip2/include -I$BP/opt/zlib/include -I$BP/opt/xz/include"
    export LDFLAGS="$LDFLAGS -L$BP/opt/bzip2/lib -L$BP/opt/zlib/lib -L$BP/opt/xz/lib"
fi

if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows Static Regex Fix..."
    # 强制静态链接
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    # 关键修复：添加 -ltre -lintl -liconv 以解决 regcomp 等符号未定义问题
    # 同时保留之前的系统库
    export LIBS="-ltre -lintl -liconv -lws2_32 -lbcrypt -lcrypt32 -lshlwapi -lpsapi -lpthread"
fi

if [ "$OS_TYPE" == "linux" ]; then
    export LDFLAGS="-static"
    if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        log_info "Cross-compiling for Linux ARM64..."
        export HOST_ALIAS="aarch64-linux-gnu"
        CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
        export CC="${HOST_ALIAS}-gcc"
        export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
    fi
fi

# 5. 执行配置
log_info "Configuring with: ${CONF_FLAGS}"
./configure ${CONF_FLAGS} || { [ -f config.log ] && tail -n 50 config.log; exit 1; }

# 6. 编译与安装
log_info "Making..."
# 关键修复：只编译主程序 bcftools
# 这样即便 Makefile 里包含 plugins 逻辑，也不会被执行，从而规避 Linux 下的 relocation 报错
make -j${MAKE_JOBS} bcftools

log_info "Installing..."
# 手动安装，因为 make install 可能会尝试安装不存在的 plugins
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bcftools${EXE_EXT} "${INSTALL_PREFIX}/bin/"
# 如果有配套脚本，一并拷贝
if [ -d "misc" ]; then
    cp -f misc/*.pl misc/*.py "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
fi

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi
