#!/bin/bash
# 通用工具函数 - 跨平台兼容（Linux/macOS/Windows-MSYS2）
# 最终修复：日志同时输出到stderr和logs文件（解决日志上传无文件警告）
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:$PATH

# 初始化日志文件路径（基于环境变量，和标准化目录一致）
if [ -n "${SOFT_NAME}" ] && [ -n "${SOFT_VERSION}" ] && [ -n "${PLATFORM}" ]; then
    LOG_DIR="${PWD}/logs/${SOFT_NAME}/${SOFT_VERSION}"
    LOG_FILE="${LOG_DIR}/${PLATFORM}-build.log"
    # 确保日志目录存在
    mkdir -p ${LOG_DIR} || true
    # 初始化日志文件（清空旧日志）
    > ${LOG_FILE} || true
else
    # 未传环境变量时，日志只输出到stderr
    LOG_FILE=""
fi

# 日志函数：同时输出到stderr（控制台）和logs文件（解决上传警告）
log_info() {
    local TIME=$(date +"%Y-%m-%d %H:%M:%S")
    local LOG_CONTENT="[INFO]  ${TIME} $1"
    # 输出到stderr
    echo -e ${LOG_CONTENT} >&2
    # 写入日志文件（如果路径有效）
    if [ -n "${LOG_FILE}" ]; then
        echo -e ${LOG_CONTENT} >> ${LOG_FILE}
    fi
}

log_error() {
    local TIME=$(date +"%Y-%m-%d %H:%M:%S")
    local LOG_CONTENT="[ERROR]  ${TIME} $1"
    # 输出到stderr（红色）
    echo -e "\033[31m${LOG_CONTENT}\033[0m" >&2
    # 写入日志文件（如果路径有效）
    if [ -n "${LOG_FILE}" ]; then
        echo -e ${LOG_CONTENT} >> ${LOG_FILE}
    fi
    exit 1
}

# 检查入参是否为空
check_param() {
    local PARAM_NAME=$1
    local PARAM_VALUE=$2
    if [ -z "${PARAM_VALUE}" ]; then
        log_error "参数为空：${PARAM_NAME}"
    fi
}

# 跨平台兼容的realpath
realpath_compat() {
    if [ -x "$(command -v realpath)" ]; then
        realpath "$1"
    else
        cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")"
    fi
}

# 路径标准化（别名）
normalize_path() {
    realpath_compat "$1"
}

# 检测操作系统
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

# get_platform别名
get_platform() {
    detect_os
}

# 获取系统架构
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

# 检查目录是否存在
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

# 标准化产物名
get_artifact_name() {
    local SOFT_NAME=$1
    local SOFT_VERSION=$2
    local PLATFORM=$3
    local ARCH=$4
    echo "${SOFT_NAME}-${SOFT_VERSION}-${PLATFORM}-${ARCH}"
}
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

log_err() {
    echo -e "\033[31m[ERROR]\033[0m $1"
    exit 1
}

