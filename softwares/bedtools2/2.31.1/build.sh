#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid: '$SRC_PATH'"
fi
cd "${SRC_PATH}"
log_info "Building bedtools2 in: $(pwd)"

# 3. 准备基础变量
export CXX="g++"
# 核心改变：不使用 make static，改为使用 make 并手动注入参数
MAKE_TARGET="all"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Optimization for Windows (MSYS2)..."
        # 修复 int64_t 报错，并确保静态链接
        # -D_FILE_OFFSET_BITS=64 是 HTSlib 必需的
        export CXXFLAGS="-O3 -include stdint.h -D_FILE_OFFSET_BITS=64"
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        # Windows 编译 HTSlib 必须链接 ws2_32
        export BT_LIBS="-lz -lbz2 -llzma -lpthread -lws2_32"
        ;;

    "macos")
        log_info "Optimization for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CXXFLAGS="-O3 -I$BP/opt/zlib/include -I$BP/opt/bzip2/include -I$BP/opt/xz/include"
        export LDFLAGS="-L$BP/opt/zlib/lib -L$BP/opt/bzip2/lib -L$BP/opt/xz/lib"
        export BT_LIBS="-lz -lbz2 -llzma -lpthread"
        ;;

    "linux")
        log_info "Optimization for Linux..."
        # 放弃全静态，改用“半静态”编译，这能解决 relocation 报错，且能在 99% 的 Linux 上运行
        export CXXFLAGS="-O3 -D_FILE_OFFSET_BITS=64"
        export LDFLAGS="-static-libgcc -static-libstdc++"
        export BT_LIBS="-lz -lbz2 -llzma -lpthread"
        
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
            log_info "Cross-compiling for Linux ARM64..."
            export CXX="aarch64-linux-gnu-g++"
            export AR="aarch64-linux-gnu-ar"
            # 交叉编译需要指定库搜索路径
            export LDFLAGS="${LDFLAGS} -L/usr/lib/aarch64-linux-gnu"
        fi
        ;;
esac

# 5. 预处理：解决版本文件生成失败问题
mkdir -p src/utils/version
echo "#define VERSION_GIT \"v${PKG_VER}\"" > src/utils/version/version_git.h

# 6. 执行编译
log_info "Cleaning..."
make clean || true

log_info "Running: make -j${MAKE_JOBS} ${MAKE_TARGET}"
# 注意：我们将 BT_LIBS 传给 make，强制覆盖 Makefile 内部的库定义
make -j${MAKE_JOBS} ${MAKE_TARGET} CXX="$CXX" BT_LIBS="$BT_LIBS"

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"

if [ -f "bin/bedtools" ]; then
    cp -f bin/bedtools "${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
    log_info "Primary binary bedtools copied."
else
    log_err "Build failed: bin/bedtools not found"
    exit 1
fi

# 拷贝 bin 目录下的所有其他工具和脚本
log_info "Copying auxiliary tools..."
cp -r bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
log_info "Verifying $FINAL_BIN ..."
file "$FINAL_BIN" || true
