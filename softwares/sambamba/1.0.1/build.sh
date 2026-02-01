#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba (Surgical Fix Mode) in: $(pwd)"

# 3. 准备 BioD
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 环境准备：锁定编译器
if [ "$OS_TYPE" == "windows" ]; then
    LDC_POSIX_EXE=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    LDC_BIN_DIR=$(dirname "$LDC_POSIX_EXE")
    export PATH="$LDC_BIN_DIR:$PATH"
    export DC=$(cygpath -w "$LDC_POSIX_EXE")
    log_info "Using DC: $DC"
else
    export DC=$(which ldc2)
fi

# 5. 【核心修复 A】修复 BioD 模块名引用
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Fixing BioD module references for Windows..."
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 【核心修复 B】修复 SIGPIPE (仅针对报错的 pileup.d，且遵守 module 语法)
if [ "$OS_TYPE" == "windows" ] && [ -f "sambamba/pileup.d" ]; then
    log_info "Patching SIGPIPE in pileup.d..."
    # 先删掉之前可能的错误补丁（防止重复运行报错）
    sed -i '/version(Windows) { enum SIGPIPE/d' sambamba/pileup.d
    # 精准插入：在 module 声明行之后追加补丁
    sed -i '/^module /a version(Windows) { enum SIGPIPE = 13; }' sambamba/pileup.d
fi

# 7. 【核心修复 C】修复 BufferedFile 句柄错误 (核心报错点)
if [ "$OS_TYPE" == "windows" ] && [ -f "sambamba/utils/common/file.d" ]; then
    log_info "Patching BufferedFile in sambamba/utils/common/file.d..."
    # Windows 的 BufferedFile 构造函数需要 void* 句柄，而不是 int
    # 采用更宽泛的匹配，将 (0, (1, (2 全部转义
    sed -i 's/BufferedFile(0/BufferedFile(cast(void*)0/g' sambamba/utils/common/file.d
    sed -i 's/BufferedFile(1/BufferedFile(cast(void*)1/g' sambamba/utils/common/file.d
    sed -i 's/BufferedFile(2/BufferedFile(cast(void*)2/g' sambamba/utils/common/file.d
fi

# 8. 手动创建版本信息文件 (避开 Python 路径拼接 Bug)
log_info "Preparing ldc_version_info_.d..."
mkdir -p utils
cat > utils/ldc_version_info_.d <<EOF
module utils.ldc_version_info_;
enum LDC_VERSION_STRING = "${PKG_VER} (BioUnix Build)";
enum DMD_VERSION_STRING = "2.098.1";
enum LLVM_VERSION_STRING = "12.0.1";
enum BOOTSTRAP_VERSION_STRING = "LDC";
EOF

# 9. 【核心修复 D】修改 meson.build 绕过路径拼接 Bug
if [ -f "meson.build" ]; then
    log_info "Patching meson.build to use relative paths..."
    # 强制修改版本文件路径为相对路径，避开 D:/ 与 /d/ 混合导致的 Python 崩溃
    sed -i "s|version_info_d_fname = .*|version_info_d_fname = files('utils/ldc_version_info_.d')|g" meson.build
    # 移除 meson.build 里的 run_command 块
    sed -i '/run_command(mkdir_prog/,/endif/d' meson.build
    sed -i "/run_command('python3'/,/endif/d" meson.build
    # 修正 gen_ldc_version_info.py 的路径错误
    sed -i "s|source_root + '/gen_ldc_version_info.py'|'gen_ldc_version_info.py'|g" meson.build
fi

# 10. 配置 Meson 并执行 Ninja
log_info "Starting Meson Setup..."
rm -rf build_dir
meson setup build_dir --buildtype=release --strip

log_info "Starting Ninja Build..."
ninja -C build_dir -v

# 11. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find build_dir/ -name "sambamba*" -type f -executable | head -n 1)
if [ -n "$FOUND_BIN" ]; then
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "SUCCESS: Binary at ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Build failed: Binary not found."
    exit 1
fi
