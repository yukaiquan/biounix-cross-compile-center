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

# 3. 准备 BioD (必须命名为 BioD)
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 【核心修复】环境准备：锁定编译器并更新 PATH
if [ "$OS_TYPE" == "windows" ]; then
    # 读取之前由 PowerShell 捕获的 POSIX 风格绝对路径 (/c/...)
    LDC_POSIX_EXE=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    LDC_BIN_DIR=$(dirname "$LDC_POSIX_EXE")
    
    # 关键：将 LDC 的 bin 目录加入 PATH，这样 Meson 的 find_program('ldc2') 才能成功
    export PATH="$LDC_BIN_DIR:$PATH"
    
    # 设置 DC 环境变量（Meson 识别 D 编译器的标准方式）
    # 使用 Windows 风格路径以确保编译器内部路径解析正确
    export DC=$(cygpath -w "$LDC_POSIX_EXE")
    log_info "Added $LDC_BIN_DIR to PATH"
    log_info "Set DC=$DC"
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

# 针对 Windows，我们需要确保 Meson 使用正确的后端和编译器
if [ "$OS_TYPE" == "windows" ]; then
    # 使用强制指定的编译器运行 setup
    meson setup build_dir --buildtype=release --strip
else
    meson setup build_dir --buildtype=release --strip
fi

# 7. 执行编译 (Ninja)
log_info "Running Ninja..."
ninja -C build_dir

# 8. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# Meson 通常直接生成在 build 目录下
if [ -f "build_dir/sambamba${EXE_EXT}" ]; then
    cp -f "build_dir/sambamba${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
    log_info "SUCCESS: sambamba generated."
else
    # 备用查找
    FOUND_BIN=$(find build_dir/ -name "sambamba${EXE_EXT}" -type f | head -n 1)
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/"
fi

# 9. 验证
log_info "Final Verification..."
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
