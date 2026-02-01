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

# 3. 准备 BioD (确保目录名和 Makefile 匹配)
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    # 增加重试逻辑
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 关键：锁定 LDC2 编译器的物理绝对路径
log_info "Locating D compiler (LDC2)..."

if [ "$OS_TYPE" == "windows" ]; then
    # 在 GitHub Actions 中，setup-dlang 会设置 $DC 环境变量
    # 我们需要将其转换为 MSYS2 识别的 /c/ 路径格式
    if [ -n "$DC" ]; then
        LDC_ABS_PATH=$(cygpath -u "$DC")
    else
        # 暴力搜索备用方案
        LDC_ABS_PATH=$(ls /c/hostedtoolcache/windows/LDC/*/x64/bin/ldc2.exe 2>/dev/null | head -n 1)
    fi
else
    LDC_ABS_PATH=$(which ldc2)
fi

# 最后的防错检查
if [[ -z "$LDC_ABS_PATH" || "$LDC_ABS_PATH" == "ldc2" ]]; then
    log_err "CRITICAL: Could not find full path for ldc2. DC env is: $DC"
fi

log_info "LDC2 binary LOCKED at: $LDC_ABS_PATH"

# 强制将编译器目录加入 PATH，确保 make 的子进程能看到同目录的其他 D 工具
export PATH="$(dirname "$LDC_ABS_PATH"):$PATH"

# 5. 生成版本信息 (手动处理)
log_info "Generating version info..."
mkdir -p utils
echo "module utils.ldc_version_info_; enum LDC_VERSION_INFO = \"${PKG_VER}\";" > utils/ldc_version_info_.d
echo "${PKG_VER}" > VERSION

# 6. 设置库搜索路径 (D 运行时库 Phobos)
LDC_ROOT=$(dirname $(dirname "$LDC_ABS_PATH"))
export LIBRARY_PATH="${LIBRARY_PATH}:${LDC_ROOT}/lib"

# 7. 根据平台准备参数
# 这里的引向必须包含绝对路径的双引号，防止路径中有空格
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
        # Windows 下必须明确链接 zlib 和 lz4
        export LIBS="-L-lz -L-llz4"
        mkdir -p bin
        ;;
    "macos")
        BUILD_TARGET="release"
        ;;
esac

# 8. 执行编译
log_info "Running command: make ${BUILD_TARGET} ${MAKE_OPTS}"
# 传递 BIOD_PATH 确保源码能被找到
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
