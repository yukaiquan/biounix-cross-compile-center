#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building sambamba (Shell-Safe Makefile Mode) in: $(pwd)"

# 3. 准备 BioD
if [ ! -d "BioD/bio" ]; then
    log_info "Fetching BioD library..."
    curl -L "${BIOD_URL}" -o BioD_src.tar.gz
    mkdir -p BioD
    tar -xf BioD_src.tar.gz -C BioD --strip-components=1
    rm BioD_src.tar.gz
fi

# 4. 获取 LDC2 绝对路径
if [ "$OS_TYPE" == "windows" ]; then
    LDC_ABS_PATH=$(cat "${BASE_DIR}/ldc_full_path.txt" | tr -d '\r\n')
    export PATH="$(dirname "$LDC_ABS_PATH"):$PATH"
    log_info "LDC2 Path: $LDC_ABS_PATH"
else
    LDC_ABS_PATH=$(which ldc2)
fi

# 5. 【源码手术】解决 Windows 编译兼容性
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows source patches..."
    # 修复 A: 模块名过时
    find BioD -name "*.d" -type f -exec sed -i 's/core.stdc.windows.windows/core.sys.windows.windows/g' {} +

    # 修复 B: 补全 SIGPIPE
    if [ -f "sambamba/pileup.d" ]; then
        sed -i '/^module /a version(Windows) { enum SIGPIPE = 13; }' sambamba/pileup.d
    fi

    # 修复 C: 修正 BufferedFile 句柄类型 (强制转换为 void*)
    find sambamba -name "*.d" -type f -exec sed -i 's/BufferedFile(0/BufferedFile(cast(void*)0/g' {} +
    find sambamba -name "*.d" -type f -exec sed -i 's/BufferedFile(1/BufferedFile(cast(void*)1/g' {} +
    find sambamba -name "*.d" -type f -exec sed -i 's/BufferedFile(2/BufferedFile(cast(void*)2/g' {} +
fi

# 6. 准备版本信息
mkdir -p utils bin
echo "${PKG_VER}" > VERSION
cat > utils/ldc_version_info_.d <<EOF
module utils.ldc_version_info_;
enum LDC_VERSION_STRING = "${PKG_VER} (BioUnix)";
enum DMD_VERSION_STRING = "2.098";
enum LLVM_VERSION_STRING = "12.0";
enum BOOTSTRAP_VERSION_STRING = "LDC";
EOF

# 7. 构造平台参数 (核心修复)
# 为了避开 Shell 对分号 ; 的误解，在 Windows 下我们巧妙地利用 Makefile 拼接逻辑
# 原 Makefile: -I$(BIOD_PATH)
# 我们传入: ./BioD -I./BioD/contrib/msgpack-d/src
# 结果展开为: -I./BioD -I./BioD/contrib/msgpack-d/src (完美避开分号)
if [ "$OS_TYPE" == "windows" ]; then
    MY_BIOD_PATH="./BioD -I./BioD/contrib/msgpack-d/src"
    BUILD_TARGET="release"
    export LIBS="-L-lz -L-llz4"
else
    MY_BIOD_PATH="./BioD:./BioD/contrib/msgpack-d/src"
    BUILD_TARGET="static"
fi

# 8. 执行编译
log_info "Running make with Shell-Safe BIOD_PATH..."

make -j${MAKE_JOBS} ${BUILD_TARGET} \
    D_COMPILER="$LDC_ABS_PATH" \
    LDC2="$LDC_ABS_PATH" \
    BIOD_PATH="$MY_BIOD_PATH"

# 9. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)

if [ -n "$FOUND_BIN" ]; then
    cp -f "${FOUND_BIN}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
    log_info "SUCCESS: Binary collected."
else
    log_err "Build failed: could not find output binary."
    exit 1
fi

# 10. 最终校验
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
