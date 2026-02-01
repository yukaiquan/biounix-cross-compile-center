#!/bin/bash
set -e

# 1. 环境加载
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba via Makefile in: $(pwd)"

# 3. 准备 BioD (必须严格按照 Makefile 定义的路径)
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 设置环境变量
# Makefile 需要知道 LIBRARY_PATH 来找 D 运行库
# setup-dlang 插件会自动设置一些变量，但我们需要手动补全链接参数
export LIBRARY_PATH="${LIBRARY_PATH}:/usr/lib:/usr/local/lib"

# 5. 根据平台准备参数
MAKE_OPTS="D_COMPILER=ldc2"

case "${OS_TYPE}" in
    "linux")
        log_info "Configuring for Linux Static..."
        # Linux 下使用静态编译目标
        BUILD_TARGET="static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            log_info "Cross-compiling for ARM64..."
            # LDC 交叉编译参数
            export DFLAGS="-mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
            export CC="aarch64-linux-gnu-gcc"
        fi
        ;;

    "windows")
        log_info "Configuring for Windows (MSYS2)..."
        # Windows 下 Makefile 可能不支持 'static' 目标，直接用 release
        BUILD_TARGET="release"
        # 强制添加 .exe 后缀变量（Makefile 中 OUT 定义用到了）
        # 但 Makefile 用的是 VERSION 文件，我们手动创建一个兼容名
        mkdir -p bin
        ;;

    "macos")
        log_info "Configuring for macOS..."
        BUILD_TARGET="release"
        [ -d "/opt/homebrew" ] && export LIBRARY_PATH="${LIBRARY_PATH}:/opt/homebrew/lib"
        ;;
esac

# 6. 执行编译
log_info "Running make ${BUILD_TARGET} ${MAKE_OPTS}"

# 修复：Makefile 里的 VERSION 文件可能缺失
[[ ! -f "VERSION" ]] && echo "${PKG_VER}" > VERSION

# 运行 Makefile
make -j${MAKE_JOBS} ${BUILD_TARGET} ${MAKE_OPTS}

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# Makefile 生成的文件名通常是 bin/sambamba-1.0.1
# 我们统一重命名为 sambamba
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Binary collected: sambamba${EXE_EXT}"
else
    log_err "Build failed: could not find output binary in bin/"
    exit 1
fi

# 8. 验证
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
