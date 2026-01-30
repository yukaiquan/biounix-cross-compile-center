#!/bin/bash
set -e
source config/global.env
source config/platform.env
source scripts/utils.sh

# 加载当前软件的 source 配置以获取 HTSLIB_URL
source softwares/bcftools/1.23/source.env

cd "${SRC_PATH}"
log_info "Current directory: $(pwd)"

# --- 1. 处理 HTSlib 缺失问题 ---
# GitHub 的 Source 压缩包不含 htslib，必须下载并解压到子目录
if [ ! -d "htslib" ]; then
    log_info "HTSlib not found. Downloading matching version..."
    curl -L "${HTSLIB_URL}" -o htslib.tar.gz
    mkdir -p htslib
    tar -zxf htslib.tar.gz -C htslib --strip-components=1
    rm htslib.tar.gz
fi

# --- 2. 生成 Configure 脚本 ---
# Source Tag 里的包通常没有预生成的 configure，需要运行 autoreconf
log_info "Generating configure scripts..."
autoheader
autoconf
cd htslib && autoheader && autoconf && cd ..

# --- 3. 初始化编译参数 ---
CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl"

# --- 4. 平台差异化处理 (全静态编译逻辑) ---
case "${OS_TYPE}" in
    "windows")
        log_info "Configuring for Windows (MSYS2) - Static Mode"
        # 强制静态链接
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        # Windows 下 curl 依赖的系统库
        export LIBS="-lws2_32 -lbcrypt -lcrypt32 -lshlwapi -lpsapi"
        # Windows 下插件极其麻烦，建议禁用
        CONF_FLAGS="${CONF_FLAGS} --disable-plugins"
        ;;

    "linux")
        log_info "Configuring for Linux - Full Static Mode"
        export LDFLAGS="-static"
        
        if [ "${ARCH_TYPE}" == "arm64" ] && [ "$(uname -m)" != "aarch64" ]; then
            log_info "Cross-compiling for Linux ARM64..."
            export HOST_ALIAS="aarch64-linux-gnu"
            CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
            export CC="${HOST_ALIAS}-gcc"
            export AR="${HOST_ALIAS}-ar"
            export RANLIB="${HOST_ALIAS}-ranlib"
            # 交叉编译时的静态库路径
            export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
        fi
        ;;

    "macos")
        log_info "Configuring for macOS..."
        # macOS 不支持完全静态链接（不允许静态链接系统内核库 libSystem）
        # 但我们会静态链接 htslib 的依赖
        for pkg in zlib bzip2 xz curl; do
            if [ -d "/opt/homebrew/opt/$pkg" ]; then
                export CPPFLAGS="$CPPFLAGS -I/opt/homebrew/opt/$pkg/include"
                export LDFLAGS="$LDFLAGS -L/opt/homebrew/opt/$pkg/lib"
            fi
        done
        ;;
esac

# --- 5. 执行配置、编译与安装 ---
log_info "Running ./configure ${CONF_FLAGS}"
./configure ${CONF_FLAGS} || { log_err "Configure failed. Check config.log"; exit 1; }

log_info "Building bcftools..."
make -j${MAKE_JOBS}

log_info "Installing to ${INSTALL_PREFIX}..."
make install

# --- 6. 验证产物 ---
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Successfully built: $(file $FINAL_BIN)"
else
    log_err "Build failed: $FINAL_BIN not found"
    exit 1
fi
