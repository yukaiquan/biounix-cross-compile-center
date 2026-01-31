#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building GEMMA in: $(pwd)"

# 3. 基础参数设置
# GEMMA Makefile 默认识别 WITH_OPENBLAS
MAKE_VARS="WITH_OPENBLAS=1"

# 4. 平台适配
case "${OS_TYPE}" in
    "windows")
        log_info "Configuring for Windows (MSYS2) Static..."
        # Windows 下需要强制静态链接所有运行时，并补全数学库依赖
        # 注入 -include cstdint 预防旧代码类型报错
        export CXXFLAGS="-O3 -include cstdint -static"
        # Windows 链接 OpenBLAS 通常需要连带 gfortran, quadmath 等
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        MAKE_VARS="${MAKE_VARS} SYS=MINGW"
        ;;

    "macos")
        log_info "Configuring for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        # 指向 Homebrew 库路径
        export CXXFLAGS="-O3 -I${BP}/opt/gsl/include -I${BP}/opt/openblas/include"
        export LDFLAGS="-L${BP}/opt/gsl/lib -L${BP}/opt/openblas/lib"
        ;;

    "linux")
        log_info "Configuring for Linux..."
        # Linux 推荐全静态编译
        export CXXFLAGS="-O3 -static"
        export LDFLAGS="-static"
        
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            log_info "Cross-compiling for Linux ARM64..."
            export CXX="aarch64-linux-gnu-g++"
            export AR="aarch64-linux-gnu-ar"
            # 交叉编译环境下的库路径
            export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
        fi
        ;;
esac

# 5. 执行编译
log_info "Running make with variables: ${MAKE_VARS}"
# GEMMA 默认将产物放在 bin/
make clean || true
make -j${MAKE_JOBS} ${MAKE_VARS}

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -f "bin/gemma" ]; then
    cp -f bin/gemma "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
elif [ -f "gemma" ]; then
    cp -f gemma "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
else
    # 兜底查找
    find . -name "gemma*" -type f -executable -exec cp {} "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}" \;
fi

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found!"
    exit 1
fi
