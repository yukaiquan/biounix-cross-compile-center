#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid: '$SRC_PATH'"
fi
cd "${SRC_PATH}"
log_info "Building VCFtools in: $(pwd)"

# 3. 检查并生成 configure 脚本 (如果从 Release 包解压通常已有，但补全逻辑以防万一)
if [ ! -f "configure" ]; then
    log_info "Configure script not found, running ./autogen.sh..."
    # 确保环境中有 pkg-config 和 libtool
    ./autogen.sh
fi

# 4. 初始化配置参数
CONF_FLAGS="--prefix=${INSTALL_PREFIX}"

# 5. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    log_info "Applying macOS Homebrew paths..."
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    export CPPFLAGS="$CPPFLAGS -I$BP/opt/zlib/include"
    export LDFLAGS="$LDFLAGS -L$BP/opt/zlib/lib"
fi

if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows Static, Regex & Winsock Fix..."
    # 强制静态链接
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    # 核心修复：
    # -ltre -lintl -liconv: 解决正则库 regcomp 报错
    # -lws2_32: 解决 knetfile.c 里的 socket/connect 等网络接口报错 (Winsock2)
    export LIBS="-ltre -lintl -liconv -lws2_32"
fi

if [ "$OS_TYPE" == "linux" ]; then
    log_info "Applying Linux Static Flags..."
    export LDFLAGS="-static"
    
    if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
        log_info "Cross-compiling for Linux ARM64..."
        export HOST_ALIAS="aarch64-linux-gnu"
        CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
        export CC="${HOST_ALIAS}-gcc"
        export CXX="${HOST_ALIAS}-g++"
        export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
    fi
fi

# 6. 执行配置、编译与安装
log_info "Running ./configure ${CONF_FLAGS}"
./configure ${CONF_FLAGS} || { [ -f config.log ] && tail -n 50 config.log; exit 1; }

log_info "Running make..."
make -j${MAKE_JOBS}

log_info "Running make install..."
make install

# 7. 验证产物
FINAL_BIN="${INSTALL_PREFIX}/bin/vcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful! Binary format:"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "VCFtools built and installed to ${INSTALL_PREFIX}/bin/"
