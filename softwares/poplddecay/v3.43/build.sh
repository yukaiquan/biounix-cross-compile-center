#!/bin/bash
# softwares/poplddecay/v3.43/build.sh
# PopLDdecay v3.43 跨平台静态编译脚本（Linux/macOS/Windows-MSYS2）
set -e  # 出错立即退出

# 静态编译参数（关键：-static 生成纯静态二进制，无系统依赖）
CFLAGS="-static -O3"
CXXFLAGS="-static -O3"
LDFLAGS="-static -lz"

# 编译（PopLDdecay源码根目录有Makefile，直接make）
make clean || true  # 先清理旧编译产物
make -j$(nproc) CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" LDFLAGS="${LDFLAGS}"

# 复制编译产物到工程BUILD_OUTPUT_DIR（通用脚本定义的目录）
mkdir -p ${BUILD_OUTPUT_DIR}
cp -f PopLDdecay ${BUILD_OUTPUT_DIR}/${OUTPUT_NAME}

# 验证产物（静态编译检查）
file ${BUILD_OUTPUT_DIR}/${OUTPUT_NAME}
echo "PopLDdecay v3.43 静态编译成功！产物路径：${BUILD_OUTPUT_DIR}/${OUTPUT_NAME}"
