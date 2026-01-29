#!/bin/bash
# 标准化依赖安装脚本
# 被build-cross.yml调用，传参：soft_name(软件名)、soft_version(版本号)
# 从softwares/soft_name/soft_version/config.env读取DEPENDENCIES参数，个性化安装依赖
# 跨平台支持：linux(ubuntu/debian)、macos(brew)、windows(msys2/pacman)

set -e
log_info() { echo -e "\033[32m[SCRIPTS-INSTALL-DEPS] $1\033[0m"; }
log_error() { echo -e "\033[31m[SCRIPTS-INSTALL-DEPS] $1\033[0m"; exit 1; }

# 步骤1：验证传参（来自标准化工作流）
if [ $# -ne 2 ]; then log_error "传参错误！用法：$0 <soft_name> <soft_version>"; fi
SOFT_NAME="$1"
SOFT_VERSION="$2"
# 验证软件个性化配置文件
CONFIG_ENV="$GITHUB_WORKSPACE/softwares/$SOFT_NAME/$SOFT_VERSION/config.env"
if [ ! -f "$CONFIG_ENV" ]; then log_error "软件个性化配置文件不存在！$CONFIG_ENV"; fi
# 加载软件个性化依赖配置
source "$CONFIG_ENV" || log_error "加载软件个性化配置失败！"
if [ -z "$DEPENDENCIES" ]; then log_error "软件未定义DEPENDENCIES！请检查$CONFIG_ENV"; fi
log_info "开始安装[$SOFT_NAME-$SOFT_VERSION]依赖：$DEPENDENCIES"

# 步骤2：跨平台依赖安装（标准化，所有软件复用）
# 识别平台（与工作流PLATFORM对齐）
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "mingw" ]]; then
    PLATFORM="windows"
    # Windows-MSYS2：pacman安装，适配zlib-devel（系统依赖名）
    DEPS_PACMAN=$(echo "$DEPENDENCIES" | sed 's/zlib/zlib-devel/g')
    log_info "Windows-MSYS2安装依赖：pacman -Syu --noconfirm $DEPS_PACMAN"
    pacman -Syu --noconfirm $DEPS_PACMAN || log_error "Windows依赖安装失败！"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"
    # macOS：brew安装，标准化依赖名
    log_info "macOS安装依赖：brew install $DEPENDENCIES"
    brew install $DEPENDENCIES || log_error "macOS依赖安装失败！请检查brew是否安装";
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="linux"
    # Linux-Ubuntu：apt安装，适配zlib1g-dev（系统依赖名）
    DEPS_APT=$(echo "$DEPENDENCIES" | sed -e 's/gcc/g++/g' -e 's/zlib/zlib1g-dev/g')
    log_info "Linux-Ubuntu安装依赖：apt update -y && apt install -y $DEPS_APT"
    apt update -y && apt install -y $DEPS_APT || log_error "Linux依赖安装失败！"
else
    log_error "不支持的平台！仅支持linux/macos/windows-MSYS2";
fi

log_info "✅ [$SOFT_NAME-$SOFT_VERSION]依赖安装完成！PLATFORM=$PLATFORM"
