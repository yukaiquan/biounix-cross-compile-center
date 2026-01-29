#!/bin/bash
set -e
SOFT_NAME=$1
SOFT_VER=$2

source config/global.env
source softwares/${SOFT_NAME}/${SOFT_VER}/source.env

mkdir -p "${SOURCE_DIR}"
DEST_FILE="${SOURCE_DIR}/${PKG_NAME}-${PKG_VER}.tar.gz"

if [ ! -f "$DEST_FILE" ]; then
    curl -L "$SOURCE_URL" -o "$DEST_FILE"
fi

# 解压到 build 目录
tar -zxf "$DEST_FILE" -C "$BUILD_DIR"
# 这里的路径处理需要灵活
export SRC_PATH=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "*${PKG_NAME}*" | head -n 1)
echo "SRC_PATH=${SRC_PATH}" >> $GITHUB_ENV # 传递给后续 Step
