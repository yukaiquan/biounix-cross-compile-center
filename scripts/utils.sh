#!/bin/bash
# 通用工具函数 - 跨平台兼容（Linux/macOS/Windows-MSYS2）
# 补全：check_param/get_arch/normalize_path + get_platform别名（兼容upload_artifact.sh）
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:$PATH

# 日志函数：带时间戳的彩色日志（输出到stderr）
log_info() {
    local TIME=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[INFO]  ${TIME} $1" >&2
}

log_error() {
    local TIME=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "\033[31m[ERROR]  ${TIME} $1\033[0m" >&2
    exit 1
}

# 新增：检查入参是否为空（upload_artifact.sh调用）
check_param() {
    local PARAM_NAME=$1
    local PARAM_VALUE=$2
    if [ -z "${PARAM_VALUE}" ]; then
        log_error "参数为空：${PARAM_NAME}"
    fi
}

# 跨平台兼容的realpath（解决realpath命令缺失）
realpath_compat() {
    if [ -x "$(command -v realpath)" ]; then
        realpath "$1"
    else
        cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")"
    fi
}

# 新增：路径标准化（别名，兼容upload_artifact.sh的normalize_path）
normalize_path() {
    realpath_compat "$1"
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

# 新增：get_platform别名（兼容upload_artifact.sh的函数名调用）
get_platform() {
    detect_os
}

# 新增：获取系统架构（返回x64/arm64，upload_artifact.sh调用）
get_arch() {
    local ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
    if [[ $ARCH == "x86_64" || $ARCH == "amd64" ]]; then
        echo "x64"
    elif [[ $ARCH == "aarch64" || $ARCH == "arm64" ]]; then
        echo "arm64"
    else
        log_error "不支持的架构：$ARCH"
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
