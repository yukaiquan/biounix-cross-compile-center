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

# 3. 针对 Windows 的源码“手术”
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Patching source for Windows compatibility (Disabling regressTest)..."
    # 从 Makefile 中移除 regressTest 编译目录
    sed -i 's|$(SRC_DIR)/regressTest||g' Makefile
    # 从主程序入口中注释掉 regressTest 调用
    if [ -f "src/bedtools.cpp" ]; then
        sed -i '/regressTest_main/d' src/bedtools.cpp
        sed -i '/subcommand == "regressTest"/d' src/bedtools.cpp
    fi
fi

# 4. 准备编译参数
export CXX="g++"
MAKE_TARGET="all"

case "${OS_TYPE}" in
    "windows")
        log_info "Applying Windows POSIX-Compatibility shims..."
        # 注入所有必需的定义，解决 int64 和 asprintf 问题
        export CXXFLAGS="-O3 -std=c++11 -D_GNU_SOURCE -D__USE_MINGW_ANSI_STDIO -D__int64_t=int64_t -include cstdint -include stdio.h -D_FILE_OFFSET_BITS=64"
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        # 链接 mman 和 Winsock
        export BT_LIBS="-lz -lbz2 -llzma -lpthread -lws2_32 -lmman"
        ;;

    "macos")
        log_info "Optimization for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CXXFLAGS="-O3 -std=c++11 -I$BP/opt/zlib/include -I$BP/opt/bzip2/include -I$BP/opt/xz/include"
        export LDFLAGS="-L$BP/opt/zlib/lib -L$BP/opt/bzip2/lib -L$BP/opt/xz/lib"
        export BT_LIBS="-lz -lbz2 -llzma -lpthread"
        ;;

    "linux")
        log_info "Optimization for Linux (Semi-Static)..."
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

# 5. 解决版本文件生成失败
mkdir -p src/utils/version
echo "#ifndef VERSION_GIT_H" > src/utils/version/version_git.h
echo "#define VERSION_GIT_H" >> src/utils/version/version_git.h
echo "#define VERSION_GIT \"v${PKG_VER}\"" >> src/utils/version/version_git.h
echo "#endif" >> src/utils/version/version_git.h

# 6. 执行编译
log_info "Cleaning..."
make clean || true

log_info "Running: make -j${MAKE_JOBS} ..."
# 传递 CXXFLAGS 以确保我们的宏生效
make -j${MAKE_JOBS} ${MAKE_TARGET} \
    CXX="$CXX" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    BT_LIBS="$BT_LIBS"

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"

if [ -f "bin/bedtools" ]; then
    cp -f bin/bedtools "${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
    log_info "Success: bedtools binary produced."
else
    log_err "Build failed: bin/bedtools not found."
    exit 1
fi

# 拷贝 bin 下的所有链接（Windows 下会变实际文件）和脚本
cp -r bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
file "$FINAL_BIN" || true
