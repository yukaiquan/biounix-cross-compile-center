#!/bin/bash
# 通用工具函数 - 跨平台兼容（Linux/macOS/Windows-MSYS2）
# 修复：确保基础命令可用、realpath兼容、日志函数正常

# 强制设置PATH，加载系统基础命令（解决Linux命令找不到问题）
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:$PATH

# 日志函数：带时间戳的彩色日志
log_info() {
    local TIME=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[INFO]  ${TIME} $1"
}

log_error() {
    local TIME=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "\033[31m[ERROR]  ${TIME} $1\033[0m"
    exit 1
}

# 跨平台兼容的realpath（解决realpath命令缺失）
realpath_compat() {
    if [ -x "$(command -v realpath)" ]; then
        realpath "$1"
    else
        # 兼容无realpath的环境（MSYS2/部分Linux）
        cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")"
    fi
}

# 检测操作系统（返回linux/macos/windows）
detect_os() {
    local OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    if [[ $OS == *"linux"* ]]; then
        echo "linux"
    elif [[ $OS == *"darwin"* ]]; then
        echo "macos"
    elif [[ $OS == *"mingw"* || $OS == *"msys"* ]]; then
        echo "windows"
    else
        log_error "不支持的操作系统：$OS"
    fi
}

# 检查目录是否存在，不存在则创建
check_dir() {
    if [ ! -d "$1" ]; then
        log_info "创建目录：$1"
        mkdir -p "$1" || log_error "创建目录失败：$1"
    fi
}

# 检查命令是否存在
check_cmd() {
    if [ ! -x "$(command -v "$1")" ]; then
        log_error "命令未找到，请先安装：$1"
    fi
}

# 标准化产物名：软件-版本-平台-架构
get_artifact_name() {
    local SOFT_NAME=$1
    local SOFT_VERSION=$2
    local PLATFORM=$3
    local ARCH=$4
    echo "${SOFT_NAME}-${SOFT_VERSION}-${PLATFORM}-${ARCH}"
}
