#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba using Meson in: $(pwd)"

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
    # 使用 Windows 原生路径供编译器使用
    export DC=$(cygpath -w "$LDC_POSIX_EXE")
    log_info "DC set to: $DC"
else
    export DC=$(which ldc2)
fi

# 5. 源码手术：修复 BioD 兼容性 (针对 Windows)
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching BioD for Windows..."
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 【核心修复】绕过 meson.build 内部崩溃的 Python 调用
log_info "Pre-generating version info and patching meson.build..."

# 创建目标目录
mkdir -p utils

# 手动运行原脚本本该运行的逻辑，生成版本文件到源码目录
# 这样我们就避开了 Meson 内部的路径拼接错误
if [ -f "gen_ldc_version_info.py" ]; then
    # 注意：这里我们直接在源码树的 utils/ 下生成
    python3 gen_ldc_version_info.py "$DC" "utils/ldc_version_info_.d" || \
    echo 'module utils.ldc_version_info_; enum LDC_VERSION_INFO = "1.0.1";' > utils/ldc_version_info_.d
fi

# 核心手术：修改 meson.build，让它不要自己生成文件，而是直接用我们准备好的
# 我们通过 sed 删掉那几行会报错的 run_command 逻辑
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Neutralizing problematic run_command in meson.build..."
    # 修改文件路径定义，去掉 build_root 前缀，改为相对源码路径
    sed -i "s|version_info_d_fname = .*|version_info_d_fname = 'utils/ldc_version_info_.d'|g" meson.build
    # 注释掉报错的 run_command 块（mkdir 和 python3 调用）
    sed -i '/run_command(mkdir_prog/I,+3d' meson.build
    sed -i '/run_command(.python3./I,+3d' meson.build
fi

# 7. 配置 Meson
log_info "Configuring Meson..."
rm -rf build_dir
# 显式指定使用的编译器
meson setup build_dir --buildtype=release --strip

# 8. 执行编译 (Ninja)
log_info "Running Ninja..."
ninja -C build_dir

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "build_dir/sambamba${EXE_EXT}" ]; then
    cp -f "build_dir/sambamba${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
    log_info "SUCCESS: sambamba generated."
else
    FOUND_BIN=$(find build_dir/ -name "sambamba${EXE_EXT}" -type f | head -n 1)
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/"
fi

log_info "Build complete!"
