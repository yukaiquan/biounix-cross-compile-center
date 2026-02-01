#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码目录
cd "${SRC_PATH}"
log_info "Building sambamba in: $(pwd)"

# 3. 准备 BioD (Case-sensitive Fix)
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 生成版本信息
if [ -f "gen_ldc_version_info.py" ]; then
    python3 gen_ldc_version_info.py v${PKG_VER} > ldc_version_info.d || true
fi

# 5. 设置编译器标志
LDC="ldc2"
# 关键：告诉 LDC 包含当前目录、BioD 目录和第三方目录
D_FLAGS="-O3 -release -flto=full -I=. -IBioD -Ithirdparty"

# 6. 平台适配
case "${OS_TYPE}" in
    "linux")
        D_FLAGS="${D_FLAGS} -static -L-lz -L-llz4 -L-lpthread"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            D_FLAGS="${D_FLAGS} -mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
        fi
        ;;
    "macos")
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        D_FLAGS="${D_FLAGS} -L-L${BP}/lib -L-lz -L-llz4"
        ;;
    "windows")
        # Windows 静态链接 zlib 和 lz4 的顺序
        D_FLAGS="${D_FLAGS} -static -L-lz -L-llz4"
        ;;
esac

# 7. 编译
# Sambamba 比较特殊，建议直接列出所有 .d 文件
log_info "Compiling with LDC2..."
$LDC $D_FLAGS -of=sambamba${EXE_EXT} \
    $(find sambamba/ -name "*.d") \
    $(find BioD/bio -name "*.d") \
    $(find thirdparty/ -name "*.d") \
    $([ -f ldc_version_info.d ] && echo "ldc_version_info.d")

# 8. 产物整理
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f "sambamba${EXE_EXT}" "${INSTALL_PREFIX}/bin/"

log_info "Done. Binary at: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
