#!/bin/bash
set -e
source config/global.env
source config/platform.env
source scripts/utils.sh

cd "${SRC_PATH}"
log_info "Current directory: $(pwd)"

# --- 1. 初始化配置参数 ---
# --enable-libcurl: 允许从 http/ftp/s3 读取数据
# --enable-configure-htslib: 自动配置内置的 htslib
CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl --enable-configure-htslib"

# --- 2. 平台差异化处理 ---
case "${OS_TYPE}" in
    "windows")
        log_info "Configuring for Windows (MSYS2) - Plugins Disabled"
        # Windows 静态编译需要链接一些系统基础库 (ws2_32 等是 curl 需要的)
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        export LIBS="-lws2_32 -lbcrypt -lcrypt32 -lshlwapi"
        # 禁用插件以简化编译，Windows 下插件机制极度复杂且不稳
        CONF_FLAGS="${CONF_FLAGS} --disable-plugins"
        ;;

    "macos")
        log_info "Configuring for macOS..."
        # macOS 很难做到完全静态（系统库不允许），但我们可以静态链接 htslib 的依赖
        # 帮助 configure 找到 Homebrew 的路径
        for pkg in zlib bzip2 xz curl; do
            if [ -d "/opt/homebrew/opt/$pkg" ]; then
                export CPPFLAGS="$CPPFLAGS -I/opt/homebrew/opt/$pkg/include"
                export LDFLAGS="$LDFLAGS -L/opt/homebrew/opt/$pkg/lib"
            fi
        done
        # macOS 下强制静态通常会导致编译失败，我们采用默认动态链接系统库，静态链接内部库
        ;;

    "linux")
        # 处理全静态编译
        export LDFLAGS="-static"
        
        if [ "${ARCH_TYPE}" == "arm64" ] && [ "$(uname -m)" != "aarch64" ]; then
            log_info "Cross-compiling for Linux ARM64..."
            export HOST_ALIAS="aarch64-linux-gnu"
            CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
            export CC="${HOST_ALIAS}-gcc"
            export AR="${HOST_ALIAS}-ar"
            export RANLIB="${HOST_ALIAS}-ranlib"
            # 指向交叉编译的库路径
            export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
        fi
        ;;
esac

# --- 3. 配置、编译与安装 ---
log_info "Step: Running configure..."
./configure ${CONF_FLAGS} || { log_err "Configure failed. See config.log"; exit 1; }

log_info "Step: Running make..."
# 注意：bcftools 编译比较耗时，MAKE_JOBS 建议设为 nproc
make -j${MAKE_JOBS}

log_info "Step: Running install..."
make install

# --- 4. 验证与清理 ---
log_info "Verifying binary..."
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    file "$FINAL_BIN" || true
    log_info "Success: $FINAL_BIN created."
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi
