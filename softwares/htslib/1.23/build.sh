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
# 禁用 shared library，只编译静态库 + 可执行文件
if [ "$OS_TYPE" == "macos" ]; then
    # macOS 使用动态链接（brew 已提供库）
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --enable-libcurl --disable-shared"
else
    # Linux/Windows 只编译静态库
    CONF_FLAGS="--prefix=${INSTALL_PREFIX} --disable-shared"
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
    # Windows MSYS2 没有 libtre，禁用正则功能
    CONF_FLAGS="${CONF_FLAGS} --disable-regex"
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
        CONF_FLAGS="${CONF_FLAGS} --host=${HOST_ALIAS} --disable-bz2 --disable-lzma --disable-gcs --disable-s3 --disable-curl"
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

# 6. 编译（禁用 shared library）
log_info "Building static library and binaries..."

# 只编译静态库和可执行文件
make -j${MAKE_JOBS} lib-static 2>/dev/null || true
make -j${MAKE_JOBS} 2>/dev/null || true

# 7. 手动安装（避免 make install 触发 .so 构建）
log_info "Installing artifacts..."
mkdir -p "${INSTALL_PREFIX}/bin"
mkdir -p "${INSTALL_PREFIX}/lib"
mkdir -p "${INSTALL_PREFIX}/include/htslib"

# 复制静态库
if [ -f "libhts.a" ]; then
    cp libhts.a "${INSTALL_PREFIX}/lib/"
    log_info "Installed libhts.a"
fi

# 复制可执行文件
for bin in annot-tsv bgzip htsfile tabix; do
    if [ -f "$bin" ]; then
        cp "$bin" "${INSTALL_PREFIX}/bin/"
        log_info "Installed $bin"
    fi
done

# 复制头文件
for h in htslib/*.h; do
    if [ -f "$h" ]; then
        cp "$h" "${INSTALL_PREFIX}/include/htslib/"
    fi
done

# 复制并修改 pkg-config 文件，确保静态链接
mkdir -p "${INSTALL_PREFIX}/lib/pkgconfig"
if [ -f "htslib.pc.tmp" ]; then
    cp htslib.pc.tmp "${INSTALL_PREFIX}/lib/pkgconfig/htslib.pc"
    # 修改 .pc 文件，确保 Libs 是静态链接
    sed -i 's/-lhts.*/-lhts -lpthread -lz -lm -lbz2 -llzma/' "${INSTALL_PREFIX}/lib/pkgconfig/htslib.pc"
    log_info "Installed htslib.pc"
fi

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/htslib${EXE_EXT}"
if [ -f "$FINAL_BIN" ] || [ -f "${INSTALL_PREFIX}/lib/libhts.a" ]; then
    log_info "Build successful!"
    ls -la "${INSTALL_PREFIX}/" || true
else
    log_err "Build artifacts not found"
    exit 1
fi
