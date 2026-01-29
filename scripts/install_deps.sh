#!/bin/bash
# 通用依赖安装脚本 - 对接softwares/[软件]/[版本]/config.env的DEPS_*参数
# 按平台自动选择包管理器：Linux(apt) | Windows(MSYS2 pacman) | macOS(brew)
# 入参：$1=软件名 $2=版本号
# 核心：DEPS_LINUX/DEPS_WINDOWS/DEPS_MACOS 为对应平台的依赖包名，空格分隔

# 脚本根目录
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source $SCRIPT_DIR/utils.sh
source $SCRIPT_DIR/../config/global.env
source $SCRIPT_DIR/../config/platform.env

# 入参校验
check_param "软件名" $1
check_param "版本号" $2
export SOFT_NAME=$1
export SOFT_VERSION=$2

# 引入软件版本配置
export SOFT_CONFIG="$SCRIPT_DIR/../softwares/$SOFT_NAME/$SOFT_VERSION/config.env"
check_param "软件版本配置文件" $SOFT_CONFIG
source $SOFT_CONFIG

# 识别当前平台
export PLATFORM=$(get_platform)
INFO "开始安装依赖 | 软件：$SOFT_NAME | 版本：$SOFT_VERSION | 平台：$PLATFORM"

# 按平台加载依赖包名
case $PLATFORM in
    linux) export DEPS=$DEPS_LINUX ;;
    windows) export DEPS=$DEPS_WINDOWS ;;
    macos) export DEPS=$DEPS_MACOS ;;
esac

# 校验依赖包名
if [[ -z $DEPS ]]; then
    WARN "该平台未配置依赖，跳过安装：$PLATFORM"
    exit 0
fi
INFO "待安装依赖包：$DEPS"

# ==================== 平台专属依赖安装逻辑 ====================
case $PLATFORM in
    # Linux：apt包管理器（Debian/Ubuntu，CentOS可扩展yum/dnf）
    linux)
        INFO "更新apt源并安装依赖"
        sudo sed -i "s/deb.debian.org/$LINUX_APT_SOURCE/g" /etc/apt/sources.list
        sudo apt update $LINUX_APT_OPTS
        sudo apt install $LINUX_APT_OPTS $DEPS || { ERROR "apt安装依赖失败"; exit 1; }
        ;;
    # Windows：MSYS2 pacman包管理器（MINGW64环境）
    windows)
        INFO "MSYS2 pacman安装依赖"
        pacman -Syu $WINDOWS_PACMAN_OPTS
        pacman -S $WINDOWS_PACMAN_OPTS $DEPS || { ERROR "pacman安装依赖失败"; exit 1; }
        ;;
    # macOS：brew包管理器
    macos)
        INFO "更新brew并安装依赖"
        # 替换brew源（可选）
        # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
        # /bin/bash -c "$(curl -fsSL https://mirrors.ustc.edu.cn/misc/brew-install.sh)"
        brew update $MACOS_BREW_OPTS
        brew install $MACOS_BREW_OPTS $DEPS || { ERROR "brew安装依赖失败"; exit 1; }
        # 配置brew环境变量
        echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
        source ~/.bashrc
        ;;
esac

SUCCESS "依赖安装完成 | 平台：$PLATFORM | 依赖：$DEPS"
