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

# 4. 关键：在 Windows 下寻找 LDC2 的真实绝对路径
log_info "Locating D compiler..."
LDC_BIN_PATH=$(which ldc2 2>/dev/null || true)

if [ -z "$LDC_BIN_PATH" ] && [ "$OS_TYPE" == "windows" ]; then
    # 如果 which 找不到，去 GitHub Actions 默认缓存路径暴力搜索
    log_info "which ldc2 failed, searching in toolcache..."
    # 注意：MSYS2 里的 C 盘路径是 /c/
    LDC_BIN_PATH=$(find /c/hostedtoolcache/windows/LDC -name "ldc2.exe" 2>/dev/null | head -n 1)
fi

if [ -z "$LDC_BIN_PATH" ]; then
    log_err "CRITICAL: ldc2 compiler not found. Path: $PATH"
fi
log_info "Found compiler at: $LDC_BIN_PATH"

# 5. 生成版本信息 (手动处理)
log_info "Generating version info..."
mkdir -p utils
# 避开 gen_ldc_version_info.py 的路径问题，直接生成
echo 'module utils.ldc_version_info_; enum LDC_VERSION_INFO = "'${PKG_VER}'";' > utils/ldc_version_info_.d
[[ ! -f "VERSION" ]] && echo "${PKG_VER}" > VERSION

# 6. 设置库路径
export LIBRARY_PATH="${LIBRARY_PATH}:/usr/lib:/usr/local/lib"

# 7. 根据平台准备参数
# 关键：D_COMPILER 必须是绝对路径
MAKE_OPTS="D_COMPILER=${LDC_BIN_PATH} LDC2=${LDC_BIN_PATH}"

case "${OS_TYPE}" in
    "linux")
        BUILD_TARGET="static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            export DFLAGS="-mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
        fi
        ;;
    "windows")
        BUILD_TARGET="release"
        # Windows 静态链接库名
        export LIBS="-L-lz -L-llz4"
        mkdir -p bin
        ;;
    "macos")
        BUILD_TARGET="release"
        [ -d "/opt/homebrew" ] && export LIBRARY_PATH="${LIBRARY_PATH}:/opt/homebrew/lib"
        ;;
esac

# 8. 执行编译
# 必须显式传递 D_COMPILER，覆盖 Makefile 里的默认值
log_info "Running: make ${BUILD_TARGET} ${MAKE_OPTS}"
make -j${MAKE_JOBS} ${BUILD_TARGET} ${MAKE_OPTS} BIOD_PATH="./BioD:./BioD/contrib/msgpack-d/src"

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Binary collected: sambamba${EXE_EXT}"
else
    log_err "Build failed: binary not found."
    exit 1
fi
