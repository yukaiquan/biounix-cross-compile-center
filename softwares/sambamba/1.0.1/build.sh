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

# 3. 准备 BioD 依赖 (处理 GitHub Archive 不含子模块的问题)
# 注意：目录名必须是 BioD
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library (Case-sensitive)..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 生成版本信息 (Sambamba 编译必需步骤)
if [ -f "gen_ldc_version_info.py" ]; then
    log_info "Generating version info..."
    python3 gen_ldc_version_info.py v${PKG_VER} > ldc_version_info.d || echo "Version script failed, continuing..."
fi

# 5. 设置编译器标志
# -I. -IBioD -Ithirdparty 是 D 语言寻找模块的关键路径
LDC="ldc2"
D_FLAGS="-O3 -release -flto=full -I=. -IBioD -Ithirdparty"

# 6. 平台适配
case "${OS_TYPE}" in
    "linux")
        log_info "Configuring for Linux (Full Static)..."
        # D 语言静态链接 zlib 和 lz4 的语法
        D_FLAGS="${D_FLAGS} -static -L-lz -L-llz4"
        
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            log_info "Cross-compiling for Linux ARM64..."
            D_FLAGS="${D_FLAGS} -mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
        fi
        ;;

    "macos")
        log_info "Configuring for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        # macOS 无法全静态，需指向 Homebrew 库
        D_FLAGS="${D_FLAGS} -L-L${BP}/lib -L-lz -L-llz4"
        ;;

    "windows")
        log_info "Configuring for Windows (MSYS2)..."
        # Windows 下 LDC2 链接系统库的语法
        D_FLAGS="${D_FLAGS} -static -L-lz -L-llz4"
        ;;
esac

# 7. 执行编译
# 我们绕过复杂的 Makefile，直接调用 ldc2 编译
# Sambamba 的主入口通常是 sambamba/main.d
log_info "Compiling with LDC2..."
# 这里的编译命令参考了 sambamba 的构建逻辑
$LDC $D_FLAGS -of=sambamba${EXE_EXT} \
    $(find sambamba/ -name "*.d") \
    $(find BioD/bio -name "*.d") \
    $(find thirdparty/ -name "*.d")

# 8. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "sambamba${EXE_EXT}" ]; then
    cp -f "sambamba${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
    log_info "Build successful: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Build failed: output binary not found."
    exit 1
fi

# 9. 验证格式
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
