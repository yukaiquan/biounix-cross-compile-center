#!/bin/bash
# 通用工具函数 - 日志打印、参数校验、路径处理、平台识别
# 所有其他脚本通过 source $SCRIPT_DIR/utils.sh 引入

# ==================== 日志打印函数（彩色输出，CI友好） ====================
# 绿色：成功  红色：错误  蓝色：信息  黄色：警告
INFO() {
    echo -e "\033[34m[INFO] $(date +%Y-%m-%d\ %H:%M:%S) $*\033[0m"
}
ERROR() {
    echo -e "\033[31m[ERROR] $(date +%Y-%m-%d\ %H:%M:%S) $*\033[0m" >&2
}
SUCCESS() {
    echo -e "\033[32m[SUCCESS] $(date +%Y-%m-%d\ %H:%M:%S) $*\033[0m"
}
WARN() {
    echo -e "\033[33m[WARN] $(date +%Y-%m-%d\ %H:%M:%S) $*\033[0m"
}

# ==================== 平台识别函数（核心！返回linux/windows/macos） ====================
get_platform() {
    local OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    if [[ $OS == *"linux"* ]]; then
        echo "linux"
    elif [[ $OS == *"mingw"* || $OS == *"msys"* ]]; then
        echo "windows"
    elif [[ $OS == *"darwin"* ]]; then
        echo "macos"
    else
        ERROR "不支持的操作系统：$OS"
        exit 1
    fi
}

# ==================== 架构识别函数（返回x64/arm64） ====================
get_arch() {
    local ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
    case $ARCH in
        x86_64|amd64) echo "x64" ;;
        arm64|aarch64) echo "arm64" ;;
        *) ERROR "不支持的架构：$ARCH"; exit 1 ;;
    esac
}

# ==================== 参数校验函数（检查变量是否为空） ====================
check_param() {
    local PARAM_NAME=$1
    local PARAM_VALUE=$2
    if [[ -z $PARAM_VALUE ]]; then
        ERROR "参数未配置：$PARAM_NAME"
        exit 1
    fi
}

# ==================== 目录创建函数（不存在则创建，递归） ====================
create_dir() {
    local DIR_PATH=$1
    if [[ ! -d $DIR_PATH ]]; then
        INFO "创建目录：$DIR_PATH"
        mkdir -p $DIR_PATH || { ERROR "创建目录失败：$DIR_PATH"; exit 1; }
    fi
}

# ==================== 路径标准化函数（处理Windows/Linux路径兼容） ====================
normalize_path() {
    local PATH=$1
    # Windows/MSYS2路径转换为绝对路径
    if [[ $(get_platform) == "windows" ]]; then
        echo $(cygpath -aw $PATH | tr '\\' '/')
    else
        echo $(realpath $PATH)
    fi
}

# ==================== 日志文件初始化函数（创建日志文件，重定向输出） ====================
init_log() {
    local LOG_FILE=$1
    create_dir $(dirname $LOG_FILE)
    # 重定向标准输出/错误到日志文件，同时保留终端输出
    exec > >(tee -a $LOG_FILE) 2>&1
    INFO "日志文件初始化完成：$LOG_FILE"
}
