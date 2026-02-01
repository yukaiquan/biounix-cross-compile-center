#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba using Makefile logic in: $(pwd)"

# 3. 准备 BioD (必须命名为 BioD)
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 获取 LDC2 绝对路径 (从 PowerShell 预捕获的文件)
if [ "$OS_TYPE" == "windows" ]; then
    LDC_ABS_PATH=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    # 强制将编译器目录加入 PATH，确保 make 内部调用 ldmd2 成功
    export PATH="$(dirname "$LDC_ABS_PATH"):$PATH"
    log_info "LDC2 Path locked: $LDC_ABS_PATH"
else
    LDC_ABS_PATH=$(which ldc2)
fi

# 5. 【源码手术】解决 Windows 编译的三大顽疾
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows source patches..."

    # 修复 A: 模块名过时 (core.stdc -> core.sys)
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +

    # 修复 B: 补全缺失的 SIGPIPE 信号
    if [ -f "sambamba/pileup.d" ]; then
        sed -i '/^module /a version(Windows) { enum SIGPIPE = 13; }' sambamba/pileup.d
    fi

    # 修复 C: 修正 BufferedFile 句柄类型 (int -> void*)
    # 这是之前导致 "none of the overloads" 报错的关键
    if [ -f "sambamba/utils/common/file.d" ]; then
        sed -i 's/BufferedFile(0/BufferedFile(cast(void*)0/g' sambamba/utils/common/file.d
        sed -i 's/BufferedFile(1/BufferedFile(cast(void*)1/g' sambamba/utils/common/file.d
        sed -i 's/BufferedFile(2/BufferedFile(cast(void*)2/g' sambamba/utils/common/file.d
    fi
    
    # 路径分隔符设置
    P_SEP=";"
else
    P_SEP=":"
fi

# 6. 准备 Makefile 必需的文件 (模拟 build-setup 目标)
log_info "Pre-generating version files..."
mkdir -p utils bin
echo "${PKG_VER}" > VERSION
cat > utils/ldc_version_info_.d <<EOF
module utils.ldc_version_info_;
enum LDC_VERSION_STRING = "${PKG_VER} (BioUnix)";
enum DMD_VERSION_STRING = "2.098";
enum LLVM_VERSION_STRING = "12.0";
enum BOOTSTRAP_VERSION_STRING = "LDC";
EOF

# 7. 根据平台执行 Make
# 我们通过命令行直接覆盖 Makefile 里的变量
# BIOD_PATH 必须根据平台使用正确的 P_SEP (; 或 :)
MY_BIOD_PATH="./BioD${P_SEP}./BioD/contrib/msgpack-d/src"

log_info "Starting Make with overridden variables..."

if [ "$OS_TYPE" == "windows" ]; then
    # Windows 下走 release 目标，并强制指定编译器绝对路径
    # LIBS 必须包含 zlib 和 lz4
    make -j${MAKE_JOBS} release \
        D_COMPILER="$LDC_ABS_PATH" \
        LDC2="$LDC_ABS_PATH" \
        BIOD_PATH="$MY_BIOD_PATH" \
        LIBS="-L-lz -L-llz4"
elif [ "$OS_TYPE" == "linux" ]; then
    # Linux 走全静态编译
    make -j${MAKE_JOBS} static \
        D_COMPILER="$LDC_ABS_PATH" \
        BIOD_PATH="$MY_BIOD_PATH"
else
    # Mac
    make -j${MAKE_JOBS} release \
        D_COMPILER="$LDC_ABS_PATH" \
        BIOD_PATH="$MY_BIOD_PATH"
fi

# 8. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# Makefile 生成的产物名类似于 bin/sambamba-1.0.1
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "SUCCESS: Binary at ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    log_err "Build failed: binary not found in bin/"
    exit 1
fi
