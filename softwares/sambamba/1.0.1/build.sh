#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba (Windows API Fix Mode) in: $(pwd)"

# 3. 准备 BioD
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 环境准备
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
    log_info "Fixing BioD module references..."
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 【核心修复 B】修复 SIGPIPE 报错 (仅限 pileup.d)
if [ "$OS_TYPE" == "windows" ] && [ -f "sambamba/pileup.d" ]; then
    log_info "Patching SIGPIPE in pileup.d..."
    # 精准插入到 module 声明之后，不破坏语法
    sed -i '/module /a version(Windows) { enum SIGPIPE = 13; }' sambamba/pileup.d
fi

# 7. 【核心修复 C】修复 BufferedFile 构造函数句柄类型错误
if [ "$OS_TYPE" == "windows" ] && [ -f "sambamba/utils/common/file.d" ]; then
    log_info "Patching BufferedFile handles in sambamba/utils/common/file.d..."
    # 将 0, 1, 2 强制转换为 void* 以匹配 Windows HANDLE 类型
    sed -i 's/new BufferedFile(0/new BufferedFile(cast(void*)0/g' sambamba/utils/common/file.d
    sed -i 's/new BufferedFile(1/new BufferedFile(cast(void*)1/g' sambamba/utils/common/file.d
    sed -i 's/new BufferedFile(2/new BufferedFile(cast(void*)2/g' sambamba/utils/common/file.d
fi

# 8. 手动创建版本信息文件
log_info "Preparing version info..."
mkdir -p utils
cat > utils/ldc_version_info_.d <<EOF
module utils.ldc_version_info_;
enum LDC_VERSION_STRING = "${PKG_VER} (BioUnix Build)";
enum DMD_VERSION_STRING = "2.098.1";
enum LLVM_VERSION_STRING = "12.0.1";
enum BOOTSTRAP_VERSION_STRING = "LDC";
EOF

# 9. 修改 meson.build 逻辑
if [ -f "meson.build" ]; then
    log_info "Patching meson.build..."
    sed -i "s|version_info_d_fname = .*|version_info_d_fname = files('utils/ldc_version_info_.d')|g" meson.build
    sed -i '/run_command(mkdir_prog/,/endif/d' meson.build
    sed -i "/run_command('python3'/,/endif/d" meson.build
fi

# 10. 配置 Meson 并执行 Ninja
log_info "Running Meson and Ninja..."
rm -rf build_dir
meson setup build_dir --buildtype=release --strip
ninja -C build_dir

# 11. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# 搜索产物名（兼容 sambamba.exe）
FOUND_BIN=$(find build_dir/ -name "sambamba*" -type f -executable | head -n 1)
if [ -n "$FOUND_BIN" ]; then
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Build successful!"
else
    log_err "Build failed: Binary not found."
    exit 1
fi
