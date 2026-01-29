#!/bin/bash
# 通用依赖安装脚本 - 按软件/版本/平台安装编译依赖
# 入参：$1=软件名 $2=版本号
# 修复：macOS brew去掉-y参数、Linux安装coreutils、跨平台兼容

# 引入工具函数
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source ${SCRIPT_DIR}/utils.sh

# 检查入参
if [ $# -ne 2 ]; then
    log_error "入参错误！用法：$0 <软件名> <版本号>"
fi

SOFT_NAME=$1
SOFT_VERSION=$2
PLATFORM=$(detect_os)
log_info "开始安装依赖 | 软件：${SOFT_NAME} | 版本：${SOFT_VERSION} | 平台：${PLATFORM}"

# 加载软件专属依赖配置（softwares/软件/版本/deps.env）
DEPS_CONFIG="${SCRIPT_DIR}/../softwares/${SOFT_NAME}/${SOFT_VERSION}/deps.env"
if [ ! -f "${DEPS_CONFIG}" ]; then
    log_error "依赖配置文件不存在：${DEPS_CONFIG}"
fi
source ${DEPS_CONFIG}
log_info "待安装依赖包：${DEPS}"

# 按平台安装依赖
case ${PLATFORM} in
    linux)
        # Ubuntu/Debian系列，先装coreutils（解决realpath/uname等命令缺失）
        log_info "更新apt并安装依赖（先装coreutils）"
        sudo apt-get update -y
        sudo apt-get install -y coreutils ${DEPS} || log_error "apt安装依赖失败"
        ;;
    macos)
        # Homebrew：核心修复！去掉-y参数（brew无-y选项）
        log_info "更新brew并安装依赖"
        brew update || log_info "brew更新失败，继续安装依赖"
        brew install ${DEPS} || log_error "brew安装依赖失败"
        ;;
    windows)
        # Windows-MSYS2/MINGW64，用pacman安装
        log_info "更新pacman并安装依赖"
        pacman -Syu --noconfirm ${DEPS} || log_error "pacman安装依赖失败"
        ;;
    *)
        log_error "不支持的平台：${PLATFORM}"
        ;;
esac

log_info "依赖安装完成 | 软件：${SOFT_NAME} | 版本：${SOFT_VERSION}"
exit 0
