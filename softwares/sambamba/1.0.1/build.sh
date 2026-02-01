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

# 4. 【核心修复】源码手术：修复旧版 BioD 的 Windows 兼容性
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching BioD source for modern LDC compatibility..."
    # 修复过时的 Windows 模块引用
    find BioD -name "*.d" -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 5. 锁定编译器路径
if [ "$OS_TYPE" == "windows" ]; then
    LDC_ABS_PATH=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
else
    LDC_ABS_PATH=$(which ldc2)
fi
log_info "LDC2 Path: $LDC_ABS_PATH"

# 6. 准备版本文件
mkdir -p utils
echo "module utils.ldc_version_info_; enum LDC_VERSION_INFO = \"${PKG_VER}\";" > utils/ldc_version_info_.d
echo "${PKG_VER}" > VERSION

# 7. 环境准备
LDC_ROOT=$(dirname $(dirname "$LDC_ABS_PATH"))
export LIBRARY_PATH="${LIBRARY_PATH}:${LDC_ROOT}/lib"
export PATH="$(dirname "$LDC_ABS_PATH"):$PATH"

# --- 8. 执行编译 (直接使用精心构造的 DFLAGS 避开 Makefile 分隔符陷阱) ---
# 定义包含路径
INC_PATHS="-I. -IBioD -IBioD/contrib/msgpack-d/src -Ithirdparty"
COMMON_FLAGS="-O3 -release -enable-inlining -boundscheck=off"

log_info "Compiling..."

if [ "$OS_TYPE" == "windows" ]; then
    # Windows 下手动调用 LDC2 编译
    # 我们使用 -vcolumns 帮助排查，并显式链接 zlib, lz4
    "$LDC_ABS_PATH" $COMMON_FLAGS $INC_PATHS -of=bin/sambamba.exe \
        main.d utils/ldc_version_info_.d $(find sambamba -name "*.d") \
        $(find BioD/bio -name "*.d") $(find thirdparty -name "*.d") \
        -L-lz -L-llz4
elif [ "$OS_TYPE" == "linux" ]; then
    # Linux 走全静态编译
    STATIC_LDFLAGS="-static -L-lz -L-llz4 -L-lpthread"
    if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
        COMMON_FLAGS="${COMMON_FLAGS} -mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
    fi
    "$LDC_ABS_PATH" $COMMON_FLAGS $INC_PATHS $STATIC_LDFLAGS -of=bin/sambamba \
        main.d utils/ldc_version_info_.d $(find sambamba -name "*.d") \
        $(find BioD/bio -name "*.d") $(find thirdparty -name "*.d")
else
    # Mac
    "$LDC_ABS_PATH" $COMMON_FLAGS $INC_PATHS -L-lz -L-llz4 -of=bin/sambamba \
        main.d utils/ldc_version_info_.d $(find sambamba -name "*.d") \
        $(find BioD/bio -name "*.d") $(find thirdparty -name "*.d")
fi

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bin/sambamba${EXE_EXT} "${INSTALL_PREFIX}/bin/"

log_info "Build Successful! Binary at: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
