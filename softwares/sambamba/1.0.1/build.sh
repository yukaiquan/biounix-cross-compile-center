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
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 关键：在各平台下锁定 LDC2 的绝对路径
log_info "Locating D compiler (LDC2)..."

# 尝试从系统路径、DC环境变量或常用安装位置寻找
if command -v ldc2 >/dev/null 2>&1; then
    LDC_ABS_PATH=$(command -v ldc2)
elif [ -n "$DC" ]; then
    # setup-dlang 会设置 DC 变量 (Windows 风格)，转为 POSIX 风格
    LDC_ABS_PATH=$(cygpath -u "$DC" 2>/dev/null || echo "$DC")
else
    # 暴力搜索 GitHub Actions 缓存目录 (仅限 Windows)
    LDC_ABS_PATH=$(find /c/hostedtoolcache/windows/LDC -name "ldc2.exe" 2>/dev/null | head -n 1)
fi

if [ -z "$LDC_ABS_PATH" ]; then
    log_err "LDC2 compiler not found! Current PATH: $PATH"
fi

log_info "LDC2 locked at absolute path: $LDC_ABS_PATH"

# 强制将编译器所在的目录加入 PATH，确保 make 的子 shell 也能看到它
export PATH="$(dirname "$LDC_ABS_PATH"):$PATH"

# 5. 生成版本信息 (手动处理，避开 Makefile 调用 which ldmd2 报错)
log_info "Generating version info..."
mkdir -p utils
echo "module utils.ldc_version_info_; enum LDC_VERSION_INFO = \"${PKG_VER}\";" > utils/ldc_version_info_.d
echo "${PKG_VER}" > VERSION

# 6. 设置库搜索路径
LDC_LIB_DIR="$(dirname $(dirname "$LDC_ABS_PATH"))/lib"
export LIBRARY_PATH="${LIBRARY_PATH}:${LDC_LIB_DIR}"

# 7. 根据平台准备编译参数
# 这里的 MAKE_OPTS 必须包含绝对路径，且用双引号包裹防止路径空格导致崩溃
MAKE_OPTS="D_COMPILER=\"$LDC_ABS_PATH\" LDC2=\"$LDC_ABS_PATH\""

case "${OS_TYPE}" in
    "linux")
        BUILD_TARGET="static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            log_info "Enabling ARM64 Cross-compile flags..."
            export DFLAGS="-mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
        fi
        ;;
    "windows")
        # Windows 下使用 release 目标，ldc2 会自动根据环境处理链接
        BUILD_TARGET="release"
        # 强制静态链接
        export LIBS="-L-lz -L-llz4"
        mkdir -p bin
        ;;
    "macos")
        BUILD_TARGET="release"
        ;;
esac

# 8. 执行编译
log_info "Running: make ${BUILD_TARGET} ${MAKE_OPTS}"
# 我们通过命令行参数传递 D_COMPILER，它会覆盖 Makefile 顶部的 D_COMPILER=ldc2
make -j${MAKE_JOBS} ${BUILD_TARGET} ${MAKE_OPTS} BIOD_PATH="./BioD:./BioD/contrib/msgpack-d/src"

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# 查找生成的可执行文件（可能是 sambamba 或 sambamba-1.0.1）
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Success! Binary is at: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Build failed: Output binary not found in bin/ folder."
    exit 1
fi

# 10. 最终校验
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
