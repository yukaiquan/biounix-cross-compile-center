#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba (Safe Brute Force Mode) in: $(pwd)"

# 3. 准备 BioD
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 获取编译器绝对路径
if [ "$OS_TYPE" == "windows" ]; then
    LDC_ABS_PATH=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    log_info "LDC2 Path: $LDC_ABS_PATH"
else
    LDC_ABS_PATH=$(which ldc2)
fi

# 5. 源码手术
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Fixing BioD source code..."
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 准备版本信息
mkdir -p utils
# 手动生成版本文件，确保模块名正确
echo 'module utils.ldc_version_info_; enum LDC_VERSION_INFO = "'${PKG_VER}'";' > utils/ldc_version_info_.d

# 7. 构造编译命令 (排除干扰项)
log_info "Collecting source files (excluding non-source directories)..."

# 关键修复 1: -type f 排除文件夹。排除 etc, deb, test, doc 等干扰目录
D_FILES=$(find . -maxdepth 4 -name "*.d" -type f | grep -vE "shunit2|etc/|deb/|doc/|test/|contrib/")

# 关键修复 2: 显式加入必须的 D 源文件
D_FILES="$D_FILES main.d utils/ldc_version_info_.d"

# 设置包含路径
INC_FLAGS="-I=. -IBioD -IBioD/contrib/msgpack-d/src -Ithirdparty"
COMMON_OPTS="-O3 -release -enable-inlining -boundscheck=off"

if [ "$OS_TYPE" == "windows" ]; then
    LDFLAGS_OPTS="-L-lz -L-llz4"
else
    LDFLAGS_OPTS="-L-lz -L-llz4 -L-lpthread"
fi

# 8. 执行编译
log_info "Starting LDC2 final compilation..."

if [ "$OS_TYPE" == "windows" ]; then
    # 注意：Windows 下 D 编译器对路径很挑剔，直接使用命令运行
    "$LDC_ABS_PATH" $COMMON_OPTS $INC_FLAGS -of=bin/sambamba.exe $D_FILES $LDFLAGS_OPTS
else
    ldc2 $COMMON_OPTS $INC_FLAGS -of=bin/sambamba $D_FILES $LDFLAGS_OPTS
fi

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "bin/sambamba${EXE_EXT}" ]; then
    cp -f bin/sambamba${EXE_EXT} "${INSTALL_PREFIX}/bin/"
    log_info "SUCCESS: sambamba${EXE_EXT} created."
else
    log_err "Binary not
