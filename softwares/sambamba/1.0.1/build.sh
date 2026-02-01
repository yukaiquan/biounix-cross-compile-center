#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba in: $(pwd)"

# 3. 准备 BioD
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 编译器路径决战
# 优先使用 YAML 传进来的强制路径，其次使用 which
LDC_BIN_PATH="${LDC_FORCED_PATH}"
[[ -z "$LDC_BIN_PATH" ]] && LDC_BIN_PATH=$(which ldc2 2>/dev/null || true)

# 如果还是找不到，尝试在 Windows Toolcache 暴力定位
if [[ -z "$LDC_BIN_PATH" && "$OS_TYPE" == "windows" ]]; then
    log_info "Searching toolcache broadly..."
    LDC_BIN_PATH=$(ls /c/hostedtoolcache/windows/LDC/*/x64/bin/ldc2.exe 2>/dev/null | head -n 1)
fi

if [[ -z "$LDC_BIN_PATH" ]]; then
    log_err "LDC2 compiler not found! Path env: $PATH"
fi
log_info "LDC2 binary locked at: $LDC_BIN_PATH"

# 获取 LDC 的根目录以设置 LIBRARY_PATH (链接 Phobos 库必需)
LDC_ROOT_DIR=$(dirname $(dirname "$LDC_BIN_PATH"))

# 5. 生成版本信息与 VERSION 文件
log_info "Pre-generating version files..."
mkdir -p utils
echo "module utils.ldc_version_info_; enum LDC_VERSION_INFO = \"${PKG_VER}\";" > utils/ldc_version_info_.d
echo "${PKG_VER}" > VERSION

# 6. 设置库路径
# 必须包含 LDC 自己的 lib 目录，否则会报无法找到 phobos2-ldc 库
export LIBRARY_PATH="${LIBRARY_PATH}:${LDC_ROOT_DIR}/lib"

# 7. 根据平台准备参数
MAKE_OPTS="D_COMPILER=\"$LDC_BIN_PATH\" LDC2=\"$LDC_BIN_PATH\""

case "${OS_TYPE}" in
    "linux")
        BUILD_TARGET="static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            export DFLAGS="-mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
        fi
        ;;
    "windows")
        # Windows 下使用 release，因为静态库路径在 MinGW 下有时会被 Makefile 搞乱
        BUILD_TARGET="release"
        # 强制指定静态链接库
        export LIBS="-L-lz -L-llz4"
        mkdir -p bin
        ;;
    "macos")
        BUILD_TARGET="release"
        ;;
esac

# 8. 执行编译
log_info "Running make ${BUILD_TARGET}..."
# 显式传递 D_COMPILER 以确保绝对路径生效
make -j${MAKE_JOBS} ${BUILD_TARGET} ${MAKE_OPTS} BIOD_PATH="./BioD:./BioD/contrib/msgpack-d/src"

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Success: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Build output not found in bin/"
    exit 1
fi
