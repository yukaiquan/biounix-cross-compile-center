#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba (Meson Manual Patch Mode) in: $(pwd)"

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

# 5. 源码手术 A：修复 BioD 兼容性
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching BioD for Windows..."
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 【关键修复】手动创建完整的版本信息文件
# 这样就不需要运行那个会崩溃的 python 脚本和 meson run_command 了
log_info "Manually creating complete ldc_version_info_.d..."
mkdir -p utils
cat > utils/ldc_version_info_.d <<EOF
module utils.ldc_version_info_;
enum LDC_VERSION_STRING = "${PKG_VER} (BioUnix Build)";
enum DMD_VERSION_STRING = "2.098.1";
enum LLVM_VERSION_STRING = "12.0.1";
enum BOOTSTRAP_VERSION_STRING = "LDC";
EOF

# 7. 【核心手术】彻底切除 meson.build 里的自动化逻辑，改为手动模式
if [ -f "meson.build" ]; then
    log_info "Re-wiring meson.build to use our manual version file..."
    # 1. 寻找 version_info_d_fname 的定义行并重写它，指向我们刚才建好的文件
    sed -i "s|version_info_d_fname = .*|version_info_d_fname = files('utils/ldc_version_info_.d')|g" meson.build
    
    # 2. 注释掉所有 run_command 块（从 mkdir 到 version 生成）
    # 使用一种更安全的 sed 方式：匹配含有 run_command 的行并删除它们相关的 if 块
    sed -i '/run_command(mkdir_prog/,/endif/d' meson.build
    sed -i "/run_command('python3'/,/endif/d" meson.build
fi

# 8. 配置 Meson
log_info "Configuring Meson..."
rm -rf build_dir
meson setup build_dir --buildtype=release --strip

# 9. 执行编译 (Ninja)
log_info "Running Ninja..."
ninja -v -C build_dir

# 10. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "build_dir/sambamba${EXE_EXT}" ]; then
    cp -f "build_dir/sambamba${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
    log_info "SUCCESS: Binary created."
else
    # 备用搜索
    FOUND_BIN=$(find build_dir/ -name "sambamba${EXE_EXT}" -type f | head -n 1)
    [ -n "$FOUND_BIN" ] && cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/" || { log_err "Binary not found"; exit 1; }
fi
