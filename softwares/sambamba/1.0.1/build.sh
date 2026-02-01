#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba using DUB in: $(pwd)"

# 3. 准备 BioD 依赖
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 修复 BioD 源码兼容性 (针对 Windows)
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching BioD for Windows compatibility..."
    find BioD -name "*.d" -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +
fi

# 5. 锁定 DUB 和编译器路径 (从之前的 PowerShell 注入获取)
if [ "$OS_TYPE" == "windows" ]; then
    LDC_EXE=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    DUB_EXE=$(dirname "$LDC_EXE")/dub.exe
    log_info "DUB Path: $DUB_EXE"
else
    DUB_EXE=$(which dub)
fi

# 6. 配置 DUB 本地依赖 (告诉 DUB 去哪里找 BioD)
log_info "Registering local BioD package..."
# 使用 --pne (provider non-existent) 避免在 CI 环境下报错
"$DUB_EXE" add-local BioD 0.2.3

# 7. 执行 DUB 编译
log_info "Running DUB build..."

# 定义编译标志
# --compiler: 指定 ldc2
# -b release: 优化模式
# --combined: 将所有源码合并编译 (提高性能)
# -a x86_64: 指定架构
DUB_OPTS="--compiler=$([ "$OS_TYPE" == "windows" ] && echo "$LDC_EXE" || echo "ldc2") -b release --combined"

if [ "$OS_TYPE" == "linux" ]; then
    # Linux 下尝试全静态
    "$DUB_EXE" build $DUB_OPTS --config=static
elif [ "$OS_TYPE" == "windows" ]; then
    # Windows 下 DUB 会自动处理 .exe 后缀和库链接
    "$DUB_EXE" build $DUB_OPTS
else
    # Mac
    "$DUB_EXE" build $DUB_OPTS
fi

# 8. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# DUB 编译出的二进制文件通常就在当前目录
FOUND_BIN=$(ls sambamba sambamba.exe 2>/dev/null | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "Success! Binary: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "DUB build finished but binary not found!"
    ls -F
    exit 1
fi
