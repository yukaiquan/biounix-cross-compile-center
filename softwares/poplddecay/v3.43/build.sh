#!/bin/bash
set -e

# 1. 加载配置与工具函数
# 确保在各种 Shell 环境下都能正确找到路径
source config/global.env
source config/platform.env
# 如果 global.env 没加载 utils，这里手动加载
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码目录
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH is not defined or directory not found: '$SRC_PATH'"
fi
cd "${SRC_PATH}"
log_info "Build start in: $(pwd)"

# 3. 设置基础编译变量
CXX="g++"
CXXFLAGS="-O3 -Wall"
LDFLAGS="-lz -lpthread"

# 4. 针对不同平台进行特殊适配
log_info "Targeting OS: ${OS_TYPE} | Arch: ${ARCH_TYPE}"

case "${OS_TYPE}" in
    "windows")
        # Windows (MinGW/MSYS2) 环境
        # 强制静态链接：解决 "不兼容" 和 "找不到 zlib1.dll/libstdc++-6.dll" 问题
        CXX="g++"
        CXXFLAGS="${CXXFLAGS} -static -static-libgcc -static-libstdc++"
        LDFLAGS="-lz -lpthread"
        log_info "Windows optimization: Applied static linking."
        ;;

    "macos")
        # macOS 环境：处理 Homebrew 安装的 zlib 路径
        if [ -d "/opt/homebrew/opt/zlib" ]; then
            ZDIR="/opt/homebrew/opt/zlib"
        elif [ -d "/usr/local/opt/zlib" ]; then
            ZDIR="/usr/local/opt/zlib"
        fi

        if [ -n "$ZDIR" ]; then
            CXXFLAGS="${CXXFLAGS} -I${ZDIR}/include"
            LDFLAGS="-L${ZDIR}/lib -lz -lpthread"
            log_info "macOS optimization: Using zlib from ${ZDIR}"
        fi
        ;;

    "linux")
        # Linux 环境：重点处理 ARM64 交叉编译
        HOST_ARCH=$(uname -m)
        # 如果目标是 arm64 但当前机器是 x86_64，则启用交叉编译器
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$HOST_ARCH" != "aarch64" && "$HOST_ARCH" != "arm64" ]]; then
            log_info "Linux Cross-Compile: x86_64 -> ARM64 (aarch64)"
            CXX="aarch64-linux-gnu-g++"
            # 指向安装好的 arm64 库路径 (由 scripts/install_deps.sh 准备)
            LDFLAGS="-L/usr/lib/aarch64-linux-gnu -lz -lpthread"
        fi
        ;;
esac

# 5. 执行编译
log_info "Compiling command: ${CXX} ${CXXFLAGS} src/LD_Decay.cpp -o PopLDdecay${EXE_EXT} ${LDFLAGS}"
${CXX} ${CXXFLAGS} src/LD_Decay.cpp -o "PopLDdecay${EXE_EXT}" ${LDFLAGS}

# 6. 核心步骤：验证生成的二进制格式 (用于调试，会在 GitHub 日志中显示)
log_info "Verifying binary format..."
if command -v file &> /dev/null; then
    file "PopLDdecay${EXE_EXT}"
else
    ls -l "PopLDdecay${EXE_EXT}"
fi

# 7. 整理产物到 dist 目录
mkdir -p "${INSTALL_PREFIX}/bin"
cp "PopLDdecay${EXE_EXT}" "${INSTALL_PREFIX}/bin/"

# 8. 拷贝配套脚本
if [ -d "bin" ]; then
    log_info "Copying auxiliary scripts from bin/ folder..."
    cp -r bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
fi

log_info "Build finished successfully!"
log_info "Final binary: ${INSTALL_PREFIX}/bin/PopLDdecay${EXE_EXT}"
