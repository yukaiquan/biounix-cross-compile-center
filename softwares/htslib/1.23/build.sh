#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building htslib Release in: $(pwd)"

# 3. 初始化配置参数
# htslib 默认配置，支持静态编译
if [ "$OS_TYPE" == "macos" ]; then
    # macOS 使用动态链接（brew 已提供库）
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl"
else
    # Linux/Windows 尝试静态编译
    CONF_FLAGS="--prefix=${INSTALL_PREFIX}"
fi

# 4. 平台特定优化
if [ "$OS_TYPE" == "macos" ]; then
    log_info "Applying macOS Homebrew paths..."
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    export CPPFLAGS="$CPPFLAGS -I$BP/opt/bzip2/include -I$BP/opt/zlib/include -I$BP/opt/xz/include"
    export LDFLAGS="$LDFLAGS -L$BP/opt/bzip2/lib -L$BP/opt/zlib/lib -L$BP/opt/xz/lib"
fi

if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows Static Flags..."
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
fi

if [ "$OS_TYPE" == "linux" ]; then
    log_info "Applying Linux Static Flags..."
    export LDFLAGS="-static"
    
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

# 5. 执行配置
log_info "Configuring with: ${CONF_FLAGS}"
autoreconf -i  # 首次需要生成 configure
./configure ${CONF_FLAGS} || { [ -f config.log ] && tail -n 50 config.log; exit 1; }

# 6. 编译与安装
log_info "Making..."
make -j${MAKE_JOBS}
make install

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/htslib${EXE_EXT}"
if [ -f "$FINAL_BIN" ] || [ -f "${INSTALL_PREFIX}/lib/libhts.a" ]; then
    log_info "Build successful!"
    ls -la "${INSTALL_PREFIX}/" || true
else
    log_err "Build artifacts not found"
    exit 1
fi
