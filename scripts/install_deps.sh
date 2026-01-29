#!/bin/bash
SOFT_NAME=$1
SOFT_VER=$2
source config/platform.env
source softwares/${SOFT_NAME}/${SOFT_VER}/deps.env

log_info "Installing dependencies for ${OS_TYPE}..."

case "$OS_TYPE" in
  linux)
    sudo apt-get update
    sudo apt-get install -y $DEPS_APT
    ;;
  macos)
    brew install $DEPS_BREW
    ;;
  windows)
    # 假设在 GitHub Actions 的 MSYS2 环境运行
    pacman -S --noconfirm --needed $(echo $DEPS_MSYS2)
    ;;
esac
