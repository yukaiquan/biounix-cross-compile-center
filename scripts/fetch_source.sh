#!/bin/bash
set -e # 出错立即停止

SOFT_NAME=$1
SOFT_VER=$2

# 1. 检查参数
if [ -z "$SOFT_NAME" ] || [ -z "$SOFT_VER" ]; then
    echo "Usage: $0 <soft_name> <soft_ver>"
    exit 1
fi

# 2. 加载全局配置 (使用绝对路径或确保文件存在)
if [ -f "config/global.env" ]; then
    source config/global.env
else
    echo "Error: config/global.env not found!"
    exit 1
fi

# 3. 加载软件特定配置
SOFT_ENV="softwares/${SOFT_NAME}/${SOFT_VER}/source.env"
if [ -f "$SOFT_ENV" ]; then
    source "$SOFT_ENV"
else
    echo "Error: $SOFT_ENV not found!"
    exit 1
fi

# 4. 关键变量检查 (防止 mkdir "" 报错)
if [ -z "$SOURCE_DIR" ]; then echo "Error: SOURCE_DIR is empty"; exit 1; fi
if [ -z "$BUILD_DIR" ]; then echo "Error: BUILD_DIR is empty"; exit 1; fi

echo "Working directory: $BASE_DIR"
echo "Downloading $PKG_NAME $PKG_VER..."

# 5. 创建目录并下载
mkdir -p "${SOURCE_DIR}"
DEST_FILE="${SOURCE_DIR}/${PKG_NAME}-${PKG_VER}.tar.gz"

# 使用 curl 下载
curl -L "$SOURCE_URL" -o "$DEST_FILE"

# 6. 解压
# 清理旧的编译目录 (可选)
# rm -rf "${BUILD_DIR}/${PKG_NAME}-${PKG_VER}" 
tar -zxf "$DEST_FILE" -C "$BUILD_DIR"

# 7. 定位解压后的源码路径并导出
# 这一步很重要，找寻解压出来的文件夹名
REAL_SRC_PATH=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "*${PKG_NAME}*" | head -n 1)

if [ -z "$REAL_SRC_PATH" ]; then
    echo "Error: Could not find extracted source directory"
    exit 1
fi

# 将路径写入文件，供 GitHub Actions 读取到 $GITHUB_ENV
echo "SRC_PATH=${REAL_SRC_PATH}" > build_env.txt
echo "Source fetched to: ${REAL_SRC_PATH}"
