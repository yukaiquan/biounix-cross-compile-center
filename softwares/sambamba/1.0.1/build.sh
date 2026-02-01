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

# 4. 路径获取 (读取 PowerShell 注入的绝对路径)
LDC_ABS_PATH=""
if [ -f "${BASE_DIR}/ldc_full_path.txt" ]; then
    LDC_ABS_PATH=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    log_info "LDC2 Path: $LDC_ABS_PATH"
fi

if [[ -z "$LDC_ABS_PATH" ]]; then
    LDC_ABS_PATH=$(which ldc2 2>/dev/null || echo "ldc2")
fi

# 5. 预生成版本信息
mkdir -p utils
echo "module utils.ldc_version_info_; enum LDC_VERSION_INFO = \"${PKG_VER}\";" > utils/ldc_version_info_.d
echo "${PKG_VER}" > VERSION

# 6. 环境准备
LDC_ROOT=$(dirname $(dirname "$LDC_ABS_PATH"))
export LIBRARY_PATH="${LIBRARY_PATH}:${LDC_ROOT}/lib"
export PATH="$(dirname "$LDC_ABS_PATH"):$PATH"

# --- 7. 核心修复：处理 Windows/Linux 路径分隔符差异 ---
if [ "$OS_TYPE" == "windows" ]; then
    # Windows 原生编译器使用分号 ;
    P_SEP=";"
else
    # Linux/Mac 使用冒号 :
    P_SEP=":"
fi

# 重新组织 BIOD_PATH
MY_BIOD_PATH="./BioD${P_SEP}./BioD/contrib/msgpack-d/src"

# 8. 编译参数准备
MAKE_OPTS="D_COMPILER=\"$LDC_ABS_PATH\" LDC2=\"$LDC_ABS_PATH\" BIOD_PATH=\"$MY_BIOD_PATH\""

case "${OS_TYPE}" in
    "linux")
        BUILD_TARGET="static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            export DFLAGS="-mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
        fi
        ;;
    "windows")
        BUILD_TARGET="release"
        # Windows 静态链接库名，这里也要注意双引号
        export LIBS="-L-lz -L-llz4"
        mkdir -p bin
        ;;
    "macos")
        BUILD_TARGET="release"
        ;;
esac

# 9. 执行编译
log_info "Executing: make ${BUILD_TARGET} ${MAKE_OPTS}"
# 显式传递 BIOD_PATH 覆盖 Makefile
make -j${MAKE_JOBS} ${BUILD_TARGET} ${MAKE_OPTS}

# 10. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Success! Binary: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Output binary not found!"
    exit 1
fi
