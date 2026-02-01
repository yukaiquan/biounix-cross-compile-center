#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba (Windows Type Casting Fix) in: $(pwd)"

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
    # 获取 PowerShell 捕获的路径
    LDC_POSIX_EXE=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    LDC_BIN_DIR=$(dirname "$LDC_POSIX_EXE")
    export PATH="$LDC_BIN_DIR:$PATH"
    # 转换为原生 Windows 路径
    export DC=$(cygpath -w "$LDC_POSIX_EXE")
    log_info "Compiler DC is: $DC"
else
    export DC=$(which ldc2)
fi

# 5. 【源码手术 A】修复 BioD 模块名
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching BioD source for Windows..."
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 【源码手术 B】修复 SIGPIPE 报错 (精准定位)
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching SIGPIPE in pileup.d..."
    # 确保只在 module 声明之后插入一次
    sed -i '/module /a version(Windows) { enum SIGPIPE = 13; }' sambamba/pileup.d
fi

# 7. 【源码手术 C】修复 BufferedFile 句柄类型 (绝杀报错点)
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching BufferedFile handle types in sambamba/utils/common/file.d..."
    # 这里的正则表达式处理了 new BufferedFile(0) 到 (2) 的所有情况，强制转换为 void*
    # 兼容可能有空格的情况
    sed -i 's/BufferedFile\s*(\s*\([0-2]\)\s*/BufferedFile(cast(void*)\1/g' sambamba/utils/common/file.d
    
    # 现场打印一下修改后的内容，以便从日志确认补丁是否打上了
    log_info "Verifying patch in file.d:"
    grep "BufferedFile(cast" sambamba/utils/common/file.d || echo "Patch failed to apply!"
fi

# 8. 手动创建版本文件
log_info "Creating ldc_version_info_.d..."
mkdir -p utils
cat > utils/ldc_version_info_.d <<EOF
module utils.ldc_version_info_;
enum LDC_VERSION_STRING = "${PKG_VER} (BioUnix Build)";
enum DMD_VERSION_STRING = "2.098.1";
enum LLVM_VERSION_STRING = "12.0.1";
enum BOOTSTRAP_VERSION_STRING = "LDC";
EOF

# 9. 修改 meson.build 绕过路径拼接 Bug
if [ -f "meson.build" ]; then
    log_info "Re-wiring meson.build..."
    # 使用相对路径避开 D:/ 与 /d/ 混合
    sed -i "s|version_info_d_fname = .*|version_info_d_fname = files('utils/ldc_version_info_.d')|g" meson.build
    # 移除 run_command 块
    sed -i '/run_command(mkdir_prog/,/endif/d' meson.build
    sed -i "/run_command('python3'/,/endif/d" meson.build
fi

# 10. 配置 Meson 并执行 Ninja
log_info "Setting up Meson..."
rm -rf build_dir
meson setup build_dir --buildtype=release --strip

log_info "Running Ninja..."
ninja -C build_dir -v

# 11. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find build_dir/ -name "sambamba*" -type f -executable | head -n 1)
if [ -n "$FOUND_BIN" ]; then
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "SUCCESS: sambamba compiled and packaged."
else
    log_err "Compilation finished but binary not found."
    exit 1
fi
