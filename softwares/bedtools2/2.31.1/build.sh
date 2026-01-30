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
MAKE_TARGET="all"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Optimization for Windows (MSYS2)..."
        # 核心修复 1：使用 -include cstdint 解决 int64_t / int32_t 未定义报错
        # 核心修复 2：添加 -D_FILE_OFFSET_BITS=64 确保大文件支持
        export CXXFLAGS="-O3 -std=c++11 -include cstdint -D_FILE_OFFSET_BITS=64"
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        # 核心修复 3：Windows 必须链接 ws2_32 以支持内嵌的 HTSlib 网络功能
        export BT_LIBS="-lz -lbz2 -llzma -lpthread -lws2_32"
        ;;

    "macos")
        log_info "Optimization for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CXXFLAGS="-O3 -std=c++11 -I$BP/opt/zlib/include -I$BP/opt/bzip2/include -I$BP/opt/xz/include"
        export LDFLAGS="-L$BP/opt/zlib/lib -L$BP/opt/bzip2/lib -L$BP/opt/xz/lib"
        export BT_LIBS="-lz -lbz2 -llzma -lpthread"
        ;;

    "linux")
        log_info "Optimization for Linux..."
        # 核心修复 4：放弃 -static 全静态（会产生重定位错误），改用“半静态”
        # 这样能保证在不同 Linux 版本间的兼容性，同时不会报错
        export CXXFLAGS="-O3 -std=c++11 -D_FILE_OFFSET_BITS=64"
        export LDFLAGS="-static-libgcc -static-libstdc++"
        export BT_LIBS="-lz -lbz2 -llzma -lpthread"
        
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
            log_info "Cross-compiling for Linux ARM64..."
            export CXX="aarch64-linux-gnu-g++"
            export AR="aarch64-linux-gnu-ar"
            export LDFLAGS="${LDFLAGS} -L/usr/lib/aarch64-linux-gnu"
        fi
        ;;
esac

# 5. 预处理：解决版本文件生成失败
mkdir -p src/utils/version
echo "#ifndef VERSION_GIT_H" > src/utils/version/version_git.h
echo "#define VERSION_GIT_H" >> src/utils/version/version_git.h
echo "#define VERSION_GIT \"v${PKG_VER}\"" >> src/utils/version/version_git.h
echo "#endif" >> src/utils/version/version_git.h

# 6. 执行编译
log_info "Cleaning..."
make clean || true

log_info "Running: make -j${MAKE_JOBS} ${MAKE_TARGET}"
# 关键点：通过命令行参数强制传递 CXXFLAGS 和 BT_LIBS，确保它们覆盖 Makefile 内部变量
make -j${MAKE_JOBS} ${MAKE_TARGET} \
    CXX="$CXX" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    BT_LIBS="$BT_LIBS"

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"

# 检查生成的可执行文件
if [ -f "bin/bedtools" ]; then
    cp -f bin/bedtools "${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
    log_info "Success: bedtools binary copied."
else
    log_err "Build failed: bin/bedtools not found."
    exit 1
fi

# 拷贝配套脚本（bedtools 很多功能依赖 bin/ 下的其他小脚本）
log_info "Copying auxiliary scripts..."
cp -r bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
log_info "Verifying product format:"
file "$FINAL_BIN" || true
