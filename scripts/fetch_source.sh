#!/bin/bash
set -e
SOFT_NAME=$1
SOFT_VER=$2

source config/global.env
source softwares/${SOFT_NAME}/${SOFT_VER}/source.env

mkdir -p "${SOURCE_DIR}"
# 获取文件名
FILENAME=$(basename "${SOURCE_URL}")
DEST_FILE="${SOURCE_DIR}/${FILENAME}"

log_info "Downloading ${FILENAME}..."
curl -L "${SOURCE_URL}" -o "${DEST_FILE}"

log_info "Extracting ${FILENAME}..."
# 根据后缀名自动选择解压命令
case "${FILENAME}" in
    *.tar.gz|*.tgz)
        tar -zxf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
    *.tar.bz2)
        tar -jxf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
    *.zip)
        unzip "${DEST_FILE}" -d "${BUILD_DIR}"
        ;;
    *)
        # 兜底尝试
        tar -xf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
esac

# 定位源码路径
REAL_SRC_PATH=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "*${PKG_NAME}*" | head -n 1)
echo "SRC_PATH=${REAL_SRC_PATH}" > build_env.txt
log_info "Source ready at: ${REAL_SRC_PATH}"
