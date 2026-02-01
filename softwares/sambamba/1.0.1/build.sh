#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh
source softwares/sambamba/1.0.1/source.env

# 2. 进入源码目录
cd "${SRC_PATH}"
log_info "Building sambamba in: $(pwd)"

# 3. 补全子模块 (关键：GitHub Archive 不含子模块)
if [ ! -d "biod/math" ]; then
    log_info "Fetching missing submodules (biod)..."
    curl -L "${BIOD_URL}" -o biod.tar.gz
    mkdir -p biod
    tar -zxf biod.tar.gz -C biod --strip-components=1
    rm biod.tar.gz
fi

# 4. 准备编译参数
LDC="ldc2"
D_FLAGS="-O3 -release -flto=full"

# 5. 平台适配
case "${OS_TYPE}" in
    "linux")
        log_info "Configuring for Linux..."
        # Linux 开启静态链接
        D_FLAGS="${D_FLAGS} -static -L-lz -L-llz4"
        
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            log_info "Cross-compiling for Linux ARM64..."
            # LDC 交叉编译：指定目标架构并指向交叉链接器
            D_FLAGS="${D_FLAGS} -mtriple=aarch64-linux-gnu -gcc=aarch64-linux-gnu-gcc"
        fi
        ;;

    "macos")
        log_info "Configuring for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        D_FLAGS="${D_FLAGS} -L-L${BP}/lib -L-lz -L-llz4"
        ;;

    "windows")
        log_info "Configuring for Windows (MSYS2)..."
        # Windows 下 LDC 通常生成原生二进制
        D_FLAGS="${D_FLAGS} -static -L-lz -L-llz4"
        EXE_EXT=".exe"
        ;;
esac

# 6. 执行编译
# Sambamba 1.0.1 推荐直接调用 make，它会调用 ldc2
log_info "Running: make LDC2='${LDC}' DFLAGS='${D_FLAGS}'"
# 备注：Sambamba 的 Makefile 比较直接，我们可以直接传参覆盖
make -j${MAKE_JOBS} LDC2="${LDC}" DFLAGS="${D_FLAGS}"

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "bin/sambamba-${PKG_VER}${EXE_EXT}" ]; then
    cp -f "bin/sambamba-${PKG_VER}${EXE_EXT}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
elif [ -f "bin/sambamba${EXE_EXT}" ]; then
    cp -f "bin/sambamba${EXE_EXT}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
else
    # 查找生成的二进制
    FOUND=$(find bin/ -name "sambamba*" -type f -executable | head -n 1)
    cp -f "${FOUND}" "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
fi

# 8. 验证
log_info "Build successful! Binary: ${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}"
file "${INSTALL_PREFIX}/bin/sambamba${EXE_EXT}" || true
