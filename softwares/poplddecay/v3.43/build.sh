#!/bin/bash
# PopLDdecay v3.43 专属编译脚本 - 仅写核心编译命令，其他逻辑由通用脚本处理
# 所有参数从config.env/全局配置读取，无硬编码
# 产物输出到$BUILD_OUTPUT_DIR/$OUTPUT_NAME（通用脚本约定路径）

# 引入工具函数（可选，用于日志打印）
SCRIPT_DIR=$(cd $(dirname $0)/../../../../scripts && pwd)
source $SCRIPT_DIR/utils.sh

# 核心编译命令（与本地手动编译一致，参数从环境变量读取）
INFO "开始编译PopLDdecay v3.43 | 编译参数：CXXFLAGS=$CXXFLAGS LDFLAGS=$LDFLAGS"
g++ src/LD_Decay.cpp -o $BUILD_OUTPUT_DIR/$OUTPUT_NAME $CXXFLAGS $LDFLAGS

# 校验编译产物是否存在
if [[ -f $BUILD_OUTPUT_DIR/$OUTPUT_NAME ]]; then
    SUCCESS "PopLDdecay v3.43编译完成 | 产物路径：$BUILD_OUTPUT_DIR/$OUTPUT_NAME"
else
    ERROR "PopLDdecay v3.43编译失败 | 产物不存在：$BUILD_OUTPUT_DIR/$OUTPUT_NAME"
    exit 1
fi
