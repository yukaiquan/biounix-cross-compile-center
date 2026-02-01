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

# 4. 【核心修复】暴力锁定 LDC2 编译器的真实绝对路径
log_info "Locating D compiler (LDC2) - Brute force mode..."

LDC_ABS_PATH=""

if [ "$OS_TYPE" == "windows" ]; then
    # 策略 A: 从 setup-dlang 提供的 DC 变量转换
    if [[ -n "$DC" && "$DC" != "ldc2" ]]; then
        LDC_ABS_PATH=$(cygpath -u "$DC")
    fi

    # 策略 B: 如果 A 不行，去 Windows 默认工具缓存路径暴力查找
    if [[ -z "$LDC_ABS_PATH" || ! -f "$LDC_ABS_PATH" ]]; then
        log_info "Searching C:/hostedtoolcache for ldc2.exe..."
        # MSYS2 下 C 盘路径是 /c/
        LDC_ABS_PATH=$(find /c/hostedtoolcache/windows/LDC -name "ldc2.exe" 2>/dev/null | head -n 1)
    fi
    
    # 策略 C: 最后的挣扎，在环境变量中找带有 ldc2 的路径
    if [[ -z "$LDC_ABS_PATH" ]]; then
        LDC_ABS_PATH=$(command -v ldc2.exe 2>/dev/null || which ldc2 2>/dev/null || echo "")
    fi
else
    LDC_ABS_PATH=$(which ldc2)
fi

# 校验：确保拿到的是绝对路径（以 / 开头）
if [[ -z "$LDC_ABS_PATH" || ! "$LDC_ABS_PATH" =~ ^/ ]]; then
    log_err "CRITICAL: Could not find the absolute path of LDC2. Current PATH is: $PATH"
fi

log_info "LDC2 binary FOUND at: $LDC_ABS_PATH"

# 强制修正：将编译器所在目录加入 PATH，防止编译过程中调用同目录工具失败
export PATH="$(dirname "$LDC_ABS_PATH"):$PATH"

# 5. 生成版本信息
log_info "Pre-generating version files..."
mkdir -p utils
echo "module utils.ldc_version_info_; enum LDC_VERSION_INFO = \"${PKG_VER}\";" > utils/ldc_version_info_.d
echo "${PKG_VER}" > VERSION

# 6. 设置库搜索路径 (D 运行时库 Phobos)
# 这一步是链接成功的关键
LDC_ROOT=$(dirname $(dirname "$LDC_ABS_PATH"))
export LIBRARY_PATH="${LIBRARY_PATH}:${LDC_ROOT}/lib"
log_info "LIBRARY_PATH updated with: ${LDC_ROOT}/lib"

# 7. 根据平台准备参数
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
