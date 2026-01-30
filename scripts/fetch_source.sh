#!/bin/bash
set -e

# --- 1. 核心修复：加载工具函数和全局配置 ---
# 无论从哪里调用，都尝试加载 utils.sh
if [ -f "scripts/utils.sh" ]; then
    source scripts/utils.sh
else
    # 简单的保底定义，防止报错
    log_info() { echo "[INFO] $1"; }
fi

# 加载全局路径定义 (如 $SOURCE_DIR, $BUILD_DIR)
if [ -f "config/global.env" ]; then
    source config/global.env
fi

# --- 2. 接收参数 ---
SOFT_NAME=$1
SOFT_VER=$2

if [ -z "$SOFT_NAME" ] || [ -z "$SOFT_VER" ]; then
    echo "Usage: $0 <software_name> <version>"
    exit 1
fi

# --- 3. 加载软件特定配置 ---
SOFT_ENV="softwares/${SOFT_NAME}/${SOFT_VER}/source.env"
if [ -f "$SOFT_ENV" ]; then
    source "$SOFT_ENV"
else
    echo "Error: $SOFT_ENV not found"
    exit 1
fi

# --- 4. 准备目录 ---
# 如果 global.env 没定义这些，则设置默认值
SOURCE_DIR=${SOURCE_DIR:-"./sources"}
BUILD_DIR=${BUILD_DIR:-"./build"}
mkdir -p "${SOURCE_DIR}" "${BUILD_DIR}"

# --- 5. 下载逻辑 ---
FILENAME=$(basename "${SOURCE_URL}")
DEST_FILE="${SOURCE_DIR}/${FILENAME}"

log_info "Downloading ${SOFT_NAME} ${SOFT_VER} from ${SOURCE_URL}..."
curl -L "${SOURCE_URL}" -o "${DEST_FILE}"

# --- 6. 解压逻辑 (支持 .gz 和 .bz2) ---
log_info "Extracting ${FILENAME}..."
case "${FILENAME}" in
    *.tar.gz|*.tgz)
        tar -zxf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
    *.tar.bz2)
        tar -jxf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
    *.zip)
        unzip -q "${DEST_FILE}" -d "${BUILD_DIR}"
        ;;
    *)
        log_info "Attempting generic extraction for ${FILENAME}..."
        tar -xf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
esac

# --- 7. 定位解压后的源码目录 ---
# 排除以 .tar.gz 等结尾的文件，只找文件夹
REAL_SRC_PATH=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "*${PKG_NAME:-$SOFT_NAME}*" | head -n 1)

if [ -z "$REAL_SRC_PATH" ]; then
    echo "Error: Could not find extracted directory for ${SOFT_NAME}"
    exit 1
fi

# 关键：将路径导出，供后续 build 步骤使用
echo "SRC_PATH=${REAL_SRC_PATH}" > build_env.txt
log_info "Source successfully prepared at: ${REAL_SRC_PATH}"
