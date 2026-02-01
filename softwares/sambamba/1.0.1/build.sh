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

# 4. 智能探测 D 编译器
# 优先使用 PATH 里的 ldc2，如果没有则尝试使用环境变量 DC
LDC_BIN=$(which ldc2 2>/dev/null || echo "$DC")
if [ -z "$LDC_BIN" ]; then
    log_err "LDC2 compiler (ldc2) not found in PATH. Ensure 'path-type: inherit' is set in MSYS2 setup."
fi
log_info "Using D compiler: $LDC_BIN"

# 5. 修复版本信息生成逻辑
log_info "Generating version info..."
mkdir -p utils
# 如果 Python 脚本失败，则手动写入一个保底的版本文件
python3 ./gen_ldc_version_info.py "$LDC_BIN" > utils/ldc_version_info_.d 2>/dev/null || \
echo 'module utils.ldc_version_info_; enum LDC_VERSION_INFO = "1.0.1";' > utils/ldc_version_info_.d

# 确保 VERSION 文件存在
[[ ! -f "VERSION" ]] && echo "${PKG_VER}" > VERSION

# 6. 设置编译环境变量
# 告诉链接器寻找 Phobos 运行时库
export LIBRARY_PATH="${LIBRARY_PATH}:/usr/lib:/usr/local/lib"

# 7. 根据平台准备参数
MAKE_OPTS="D_COMPILER=$LDC_BIN LDC2=$LDC_BIN"

case "${OS_TYPE}" in
    "linux")
        log_info "Configuring for Linux Static..."
        BUILD_TARGET="static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            export DFLAGS="-mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
            export CC="aarch64-linux-gnu-gcc"
        fi
        ;;
    "windows")
        log_info "Configuring for Windows (MSYS2)..."
        BUILD_TARGET="release"
        # 强制静态链接
        export LIBS="-L-lz -L-llz4"
        mkdir -p bin
        ;;
    "macos")
        log_info "Configuring for macOS..."
        BUILD_TARGET="release"
        [ -d "/opt/homebrew" ] && export LIBRARY_PATH="${LIBRARY_PATH}:/opt/homebrew/lib"
        ;;
esac

# 8. 执行编译
log_info "Running make ${BUILD_TARGET}..."
# 指定 BIOD_PATH 覆盖 Makefile 中的定义
make -j${MAKE_JOBS} ${BUILD_TARGET} ${MAKE_OPTS} BIOD_PATH="./BioD:./BioD/contrib/msgpack-d/src"

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# 查找编译出的二进制 (Makefile 生成的文件名通常带版本号)
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Binary collected: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Build failed: could not find output binary."
    exit 1
fi

# 10. 验证
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
