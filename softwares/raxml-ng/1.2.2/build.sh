#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid"
fi
cd "${SRC_PATH}"

# 3. 定位真实根目录
if [ ! -f "CMakeLists.txt" ]; then
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi

# 4. Windows 不支持（pll-modules 与 GCC 15 不兼容）
if [ "$OS_TYPE" == "windows" ]; then
    log_warn "raxml-ng Windows build is NOT SUPPORTED due to pll-modules incompatibility with GCC 15"
    log_warn "Please download pre-built binary from: https://github.com/amkaze/raxml-ng/releases"
    exit 0
fi

# 5. CMake 编译参数
case "${OS_TYPE}" in
    "linux")
        CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DSTATIC_BUILD=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON"
        GENERATOR="Unix Makefiles"
        ;;
    "macos")
        CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DSTATIC_BUILD=OFF -DUSE_GMP=ON -DUSE_PTHREADS=ON"
        GENERATOR="Unix Makefiles"
        ;;
esac

# 6. 构建
rm -rf build_dir && mkdir build_dir && cd build_dir
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}
make -j${MAKE_JOBS} || make

# 7. 整理
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find . -name "raxml-ng*${EXE_EXT}" -type f | grep -v "test" | head -n 1)
if [ -n "$FOUND_BIN" ]; then
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
    log_info "Build successful!"
else
    log_err "raxml-ng binary not found"
    exit 1
fi
