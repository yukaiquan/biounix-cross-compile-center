#!/bin/bash
set -e

# 1. 加载基础配置与工具函数
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 加载 bcftools 特有的源码配置 (需包含 HTSLIB_URL)
source softwares/bcftools/1.23/source.env

# 2. 进入源码目录
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid: '$SRC_PATH'"
fi
cd "${SRC_PATH}"
log_info "Start building bcftools in: $(pwd)"

# 3. 准备 HTSlib (GitHub Source Tag 不含 HTSlib，必须下载)
if [ ! -d "htslib" ]; then
    log_info "HTSlib is missing. Downloading matching version..."
    curl -L "${HTSLIB_URL}" -o htslib.tar.gz
    mkdir -p htslib
    tar -zxf htslib.tar.gz -C htslib --strip-components=1
    rm htslib.tar.gz
fi

# 4. 检查并生成构建系统 (解决 autoheader 和 config.guess 缺失问题)
# 必须安装 autoconf, automake, libtool, pkg-config
log_info "Bootstrapping build system with autoreconf..."

# 先为子目录 htslib 生成构建文件
cd htslib
autoreconf -vfi
cd ..
# 为 bcftools 生成构建文件
autoreconf -vfi

# 5. 初始化配置参数
# --enable-libcurl: 支持通过 URL 直接读取 VCF/BCF
# --enable-configure-htslib: 让 bcftools 自动去配置子目录下的 htslib
CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl --enable-configure-htslib"

# 6. 针对平台定制静态编译逻辑
case "${OS_TYPE}" in
    "windows")
        log_info "Optimization for Windows (MSYS2) - Static Mode"
        # 强制静态链接
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        # Windows 下 curl/htslib 需要的系统基础库，不加会报 undefined reference
        export LIBS="-lws2_32 -lbcrypt -lcrypt32 -lshlwapi -lpsapi -lpthread"
        # Windows 下建议禁用插件，否则需要复杂的动态链接配置
        CONF_FLAGS="${CONF_FLAGS} --disable-plugins"
        ;;

    "linux")
        log_info "Optimization for Linux - Full Static Mode"
        export LDFLAGS="-static"
        
        # 交叉编译处理 (x86_64 -> ARM64)
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
            log_info "Linux Cross-Compile detected: Target ARM64"
            export HOST_ALIAS="aarch64-linux-gnu"
            CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS}"
            export CC="${HOST_ALIAS}-gcc"
            export AR="${HOST_ALIAS}-ar"
            export RANLIB="${HOST_ALIAS}-ranlib"
            # 指向 arm64 的静态库路径
            export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
        fi
        ;;

    "macos")
        log_info "Optimization for macOS..."
        # macOS 不支持内核库全静态，但我们会指向 Homebrew 的库路径
        for pkg in zlib bzip2 xz curl; do
            if [ -d "/opt/homebrew/opt/$pkg" ]; then
                export CPPFLAGS="$CPPFLAGS -I/opt/homebrew/opt/$pkg/include"
                export LDFLAGS="$LDFLAGS -L/opt/homebrew/opt/$pkg/lib"
            fi
        done
        ;;
esac

# 7. 运行配置、编译与安装
log_info "Running: ./configure ${CONF_FLAGS}"
./configure ${CONF_FLAGS} || { log_err "Configure failed. Check config.log"; exit 1; }

log_info "Running: make -j${MAKE_JOBS}"
make -j${MAKE_JOBS}

log_info "Running: make install"
make install

# 8. 产物验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bcftools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi
