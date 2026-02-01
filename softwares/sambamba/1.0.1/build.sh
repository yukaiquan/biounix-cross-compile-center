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

# 3. 准备 BioD (必须命名为 BioD，大小写敏感)
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 环境准备：告知 Meson 编译器位置
if [ "$OS_TYPE" == "windows" ]; then
    # 读取之前记录的绝对路径
    LDC_RAW_PATH=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    # 转换为 Windows 原生路径供 Meson 使用
    export DC=$(cygpath -w "$LDC_RAW_PATH")
    log_info "Setting DC=$DC"
else
    export DC=$(which ldc2)
fi

# 5. 源码手术：修复 BioD 的 Windows 兼容性
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching BioD for Windows..."
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 6. 配置 Meson
log_info "Configuring Meson..."
rm -rf build_dir
# --buildtype=release: 开启优化
# --strip: 减小二进制体积
meson setup build_dir --buildtype=release --strip

# 7. 执行编译 (Ninja)
log_info "Running Ninja..."
ninja -C build_dir

# 8. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "build_dir/sambamba${EXE_EXT}" ]; then
    cp -f "build_dir/sambamba${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
    log_info "SUCCESS: sambamba generated at ${INSTALL_PREFIX}/bin/"
else
    log_err "Build failed: Binary not found in build_dir/"
    exit 1
fi

# 9. 验证
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
