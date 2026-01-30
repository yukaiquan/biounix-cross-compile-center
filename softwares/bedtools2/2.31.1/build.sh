#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bedtools2 in: $(pwd)"

# 3. 准备编译参数
# bedtools 默认使用 g++，我们根据平台切换
export CXX="g++"
MAKE_TARGET="all"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Optimization for Windows (MSYS2)..."
        export CXXFLAGS="-O3 -static"
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        # Windows 静态编译需要明确指定依赖
        export LIBS="-lz -lbz2 -llzma -lpthread -lws2_32"
        MAKE_TARGET="static"
        ;;

    "macos")
        log_info "Optimization for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        # macOS 无法完全静态链接系统库，所以走默认 all
        export CXXFLAGS="-O3 -I$BP/opt/zlib/include -I$BP/opt/bzip2/include -I$BP/opt/xz/include"
        export LDFLAGS="-L$BP/opt/zlib/lib -L$BP/opt/bzip2/lib -L$BP/opt/xz/lib"
        MAKE_TARGET="all"
        ;;

    "linux")
        export CXXFLAGS="-O3"
        MAKE_TARGET="static" # Linux 推荐编译 static 版本实现绿色化
        
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
            log_info "Cross-compiling for Linux ARM64..."
            export CXX="aarch64-linux-gnu-g++"
            export AR="aarch64-linux-gnu-ar"
            export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
        else
            export LDFLAGS="-static"
        fi
        ;;
esac

# 5. 执行编译
log_info "Running: make clean"
make clean || true

log_info "Running: make -j${MAKE_JOBS} ${MAKE_TARGET}"
# 执行编译。注意：bedtools 编译非常占内存，如果 Runner 内存不足，请减小 -j 后的数字
make -j${MAKE_JOBS} ${MAKE_TARGET}

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"

# bedtools 会生成一个大的主程序 bedtools，以及一系列软链接
if [ -f "bin/bedtools.static" ]; then
    cp -f bin/bedtools.static "${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
elif [ -f "bin/bedtools" ]; then
    cp -f bin/bedtools "${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
fi

# 拷贝配套的脚本工具 (bedtools 包含很多 python/bash 脚本)
if [ -d "scripts" ]; then
    log_info "Copying auxiliary scripts..."
    # 过滤掉源码，只拷贝脚本
    cp -r bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
fi

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bedtools${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful! Binary format:"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bedtools2 installed to ${INSTALL_PREFIX}/bin/"
