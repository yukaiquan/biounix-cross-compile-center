#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba (Brute Force Mode) in: $(pwd)"

# 3. 准备 BioD
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 获取编译器绝对路径 (从 PowerShell 注入的文件读)
if [ "$OS_TYPE" == "windows" ]; then
    # 获取 POSIX 风格路径 (/c/...)
    LDC_POSIX_PATH=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    # 转换为 Windows 原生风格 (C:\...)，这是让原生 ldc2.exe 读懂路径的关键
    LDC_WIN_PATH=$(cygpath -w "$LDC_POSIX_PATH")
    log_info "LDC2 Windows Path: $LDC_WIN_PATH"
else
    LDC_POSIX_PATH=$(which ldc2)
fi

# 5. 源码手术：修复旧版 BioD 的 Windows 模块名
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Fixing BioD source code for modern LDC..."
    find BioD -name "*.d" -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 准备版本信息
mkdir -p utils
echo "module utils.ldc_version_info_; enum LDC_VERSION_INFO = \"${PKG_VER}\";" > utils/ldc_version_info_.d

# 7. 构造编译命令
# 注意：Windows 原生编译器不喜欢 -I./BioD，它喜欢 -IBioD 甚至绝对路径
log_info "Searching for source files..."

# 获取所有源文件列表
# 我们需要：当前目录的 .d, sambamba/ 下的 .d, BioD/ 下的 .d, thirdparty/ 下的 .d
D_FILES=$(find . -name "*.d" | grep -v "contrib/shunit2")

# 设置包含路径
if [ "$OS_TYPE" == "windows" ]; then
    # Windows 下路径分隔符用分号，且不建议带 ./
    INC_FLAGS="-I. -IBioD -IBioD/contrib/msgpack-d/src -Ithirdparty"
    LDFLAGS_OPTS="-L-lz -L-llz4"
else
    INC_FLAGS="-I. -IBioD -IBioD/contrib/msgpack-d/src -Ithirdparty"
    LDFLAGS_OPTS="-L-lz -L-llz4 -L-lpthread"
fi

COMMON_OPTS="-O3 -release -enable-inlining -boundscheck=off"

# 8. 执行编译
log_info "Starting LDC2 compilation..."

if [ "$OS_TYPE" == "windows" ]; then
    # 这里的关键是使用 $LDC_POSIX_PATH (MSYS2可以运行它)，但参数里的路径要干净
    "$LDC_POSIX_PATH" $COMMON_OPTS $INC_FLAGS -of=bin/sambamba.exe $D_FILES $LDFLAGS_OPTS
else
    # Linux/Mac
    ldc2 $COMMON_OPTS $INC_FLAGS -of=bin/sambamba $D_FILES $LDFLAGS_OPTS
fi

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "bin/sambamba${EXE_EXT}" ]; then
    cp -f bin/sambamba${EXE_EXT} "${INSTALL_PREFIX}/bin/"
    log_info "SUCCESS: Binary created at ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Compilation finished but binary not found in bin/"
    exit 1
fi
