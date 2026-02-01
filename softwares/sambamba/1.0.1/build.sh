#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba (Meson Syntax Fix) in: $(pwd)"

# 3. 准备 BioD
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 环境准备：锁定编译器 (必须配合 YAML 中的 path-type: inherit)
if [ "$OS_TYPE" == "windows" ]; then
    LDC_POSIX_EXE=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    LDC_BIN_DIR=$(dirname "$LDC_POSIX_EXE")
    export PATH="$LDC_BIN_DIR:$PATH"
    export DC=$(cygpath -w "$LDC_POSIX_EXE")
    log_info "Using DC: $DC"
else
    export DC=$(which ldc2)
fi

# 5. 源码手术 A：修复 BioD 兼容性 (针对 Windows)
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching BioD for Windows..."
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 【核心修复】源码手术 B：修复 Windows 缺失 SIGPIPE 的正确方式
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching SIGPIPE correctly (after module declaration)..."
    # 仅在报错的 pileup.d 中插入定义，且必须放在 module 声明之后
    # /module /a 的意思是“在匹配到 module 的行之后追加”
    sed -i '/module /a version(Windows) { enum SIGPIPE = 13; }' sambamba/pileup.d
fi

# 7. 手动创建完整的版本信息文件
log_info "Manually creating version file..."
mkdir -p utils
cat > utils/ldc_version_info_.d <<EOF
module utils.ldc_version_info_;
enum LDC_VERSION_STRING = "${PKG_VER} (BioUnix Build)";
enum DMD_VERSION_STRING = "2.098.1";
enum LLVM_VERSION_STRING = "12.0.1";
enum BOOTSTRAP_VERSION_STRING = "LDC";
EOF

# 8. 修改 meson.build 逻辑
if [ -f "meson.build" ]; then
    log_info "Re-wiring meson.build..."
    # 指向我们建好的版本文件
    sed -i "s|version_info_d_fname = .*|version_info_d_fname = files('utils/ldc_version_info_.d')|g" meson.build
    
    # 移除会报错的 run_command 块（适配 Windows 路径拼接 Bug）
    sed -i '/run_command(mkdir_prog/,/endif/d' meson.build
    sed -i "/run_command('python3'/,/endif/d" meson.build
fi

# 9. 配置 Meson
log_info "Configuring Meson..."
rm -rf build_dir
meson setup build_dir --buildtype=release --strip

# 10. 执行编译 (Ninja)
log_info "Running Ninja..."
# -v 开启详细模式，方便看到每一条编译指令
ninja -v -C build_dir

# 11. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "build_dir/sambamba${EXE_EXT}" ]; then
    cp -f "build_dir/sambamba${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
    log_info "SUCCESS: Binary created."
else
    FOUND_BIN=$(find build_dir/ -name "sambamba${EXE_EXT}" -type f | head -n 1)
    [ -n "$FOUND_BIN" ] && cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/" || { log_err "Binary not found"; exit 1; }
fi
