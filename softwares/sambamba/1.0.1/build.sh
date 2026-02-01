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

# 4. 【核心修复】路径获取：优先读取 PowerShell 注入的路径
log_info "Locating D compiler (LDC2)..."
LDC_ABS_PATH=""

if [ -f "${BASE_DIR}/ldc_full_path.txt" ]; then
    LDC_ABS_PATH=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    log_info "Path loaded from sync file: $LDC_ABS_PATH"
fi

# 如果文件不存在，尝试环境变量和自测（用于 Linux/Mac）
if [ -z "$LDC_ABS_PATH" ]; then
    if [ -n "$LDC_FORCED_PATH" ]; then
        LDC_ABS_PATH="$LDC_FORCED_PATH"
    else
        LDC_ABS_PATH=$(which ldc2 2>/dev/null || echo "")
    fi
fi

if [[ -z "$LDC_ABS_PATH" ]]; then
    log_err "CRITICAL: ldc2 not found! Environment is incomplete."
fi

# 5. 生成版本信息 (手动处理)
log_info "Pre-generating version files..."
mkdir -p utils
echo "module utils.ldc_version_info_; enum LDC_VERSION_INFO = \"${PKG_VER}\";" > utils/ldc_version_info_.d
echo "${PKG_VER}" > VERSION

# 6. 设置库搜索路径
LDC_ROOT=$(dirname $(dirname "$LDC_ABS_PATH"))
export LIBRARY_PATH="${LIBRARY_PATH}:${LDC_ROOT}/lib"
export PATH="$(dirname "$LDC_ABS_PATH"):$PATH"

# 7. 根据平台准备参数
# 重点：D_COMPILER 必须带双引号，防止 Windows 路径空格
MAKE_OPTS="D_COMPILER=\"$LDC_ABS_PATH\" LDC2=\"$LDC_ABS_PATH\""

case "${OS_TYPE}" in
    "linux")
        BUILD_TARGET="static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            export DFLAGS="-mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
        fi
        ;;
    "windows")
        BUILD_TARGET="release"
        export LIBS="-L-lz -L-llz4"
        mkdir -p bin
        ;;
    "macos")
        BUILD_TARGET="release"
        ;;
esac

# 8. 执行编译
log_info "Executing: make ${BUILD_TARGET} ${MAKE_OPTS}"
# 强制传递编译器路径给 make 及其子 shell
make -j${MAKE_JOBS} ${BUILD_TARGET} ${MAKE_OPTS} BIOD_PATH="./BioD:./BioD/contrib/msgpack-d/src"

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Success! Binary collected: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Build finished but output binary not found in bin/."
    exit 1
fi
