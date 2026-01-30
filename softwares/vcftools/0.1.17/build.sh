#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building VCFtools in: $(pwd)"

# 3. 检查并生成 configure 脚本 (以防万一)
if [ ! -f "configure" ]; then
    log_info "Configure script not found, running ./autogen.sh..."
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
    log_info "Applying Windows Static Fix..."
    # vcftools 内部使用了 regex，需要链接 tre 库
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    export LIBS="-ltre -lintl -liconv"
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

log_info "Making..."
make -j${MAKE_JOBS}
make install

# 7. 验证
# VCFtools 会在 bin/ 目录下生成一个二进制文件 'vcftools' 
# 和一堆 Perl 脚本（如 vcf-sort, vcf-concat 等）
FINAL_BIN="${INSTALL_PREFIX}/bin/vcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "VCFtools installation complete. Binaries and Perl scripts are in ${INSTALL_PREFIX}/bin/"
