#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba via Makefile in: $(pwd)"

# 3. 准备 BioD (确保路径大小写正确)
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 关键修复：预生成版本信息文件，绕过 Makefile 的 'which ldmd2' 报错
log_info "Pre-generating version info to bypass Makefile error..."
mkdir -p utils
# 尝试找到编译器路径，如果找不到则给个默认字符串
COMPILER_PATH=$(which ldc2 || echo "ldc2")
python3 ./gen_ldc_version_info.py "$COMPILER_PATH" > utils/ldc_version_info_.d || \
echo 'module utils.ldc_version_info_; enum LDC_VERSION_INFO = "1.0.1";' > utils/ldc_version_info_.d

# 确保 VERSION 文件存在 (Makefile 需要)
[[ ! -f "VERSION" ]] && echo "${PKG_VER}" > VERSION

# 5. 设置编译环境变量
# 告诉链接器去哪里找 D 运行时库（Phobos）
export LIBRARY_PATH="${LIBRARY_PATH}:/usr/lib:/usr/local/lib"

# 6. 根据平台准备参数
# 强制指定编译器为 ldc2
MAKE_OPTS="D_COMPILER=ldc2 LDC2=ldc2"

case "${OS_TYPE}" in
    "linux")
        log_info "Configuring for Linux Static..."
        BUILD_TARGET="static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            log_info "Cross-compiling for ARM64..."
            export DFLAGS="-mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
            export CC="aarch64-linux-gnu-gcc"
        fi
        ;;

    "windows")
        log_info "Configuring for Windows (MSYS2)..."
        # Windows 下使用 release 目标更稳，ldc2 会自动处理静态链接
        BUILD_TARGET="release"
        # 强制指定静态链接库
        export LIBS="-L-lz -L-llz4"
        # 修复 Makefile 可能生成的 bin/ 目录不存在问题
        mkdir -p bin
        ;;

    "macos")
        log_info "Configuring for macOS..."
        BUILD_TARGET="release"
        [ -d "/opt/homebrew" ] && export LIBRARY_PATH="${LIBRARY_PATH}:/opt/homebrew/lib"
        ;;
esac

# 7. 执行编译
log_info "Running: make ${BUILD_TARGET} ${MAKE_OPTS}"
# 传入 DFLAGS 确保包含 BioD 路径
make -j${MAKE_JOBS} ${BUILD_TARGET} ${MAKE_OPTS} BIOD_PATH="./BioD:./BioD/contrib/msgpack-d/src"

# 8. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# Makefile 会生成类似 bin/sambamba-1.0.1 的文件
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Binary collected: sambamba${EXE_EXT}"
else
    log_err "Build failed: could not find output binary in bin/"
    exit 1
fi

# 9. 验证
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
