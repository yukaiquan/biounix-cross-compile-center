#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

SOFT_NAME=$1
SOFT_VER=$2
source softwares/${SOFT_NAME}/${SOFT_VER}/source.env

# 2. 准备目录
mkdir -p "${SOURCE_DIR}"
rm -rf "${BUILD_DIR}" && mkdir -p "${BUILD_DIR}"

FILENAME=$(basename "${SOURCE_URL}")
DEST_FILE="${SOURCE_DIR}/${FILENAME}"

# 3. 下载
log_info "Downloading ${FILENAME}..."
[ ! -f "${DEST_FILE}" ] && curl -L "${SOURCE_URL}" -o "${DEST_FILE}"

# 4. 解压
log_info "Extracting ${FILENAME}..."
case "${FILENAME}" in
    *.tar.gz|*.tgz) tar -zxf "${DEST_FILE}" -C "${BUILD_DIR}" ;;
    *.tar.bz2)     tar -jxf "${DEST_FILE}" -C "${BUILD_DIR}" ;;
    *.zip)         unzip -qo "${DEST_FILE}" -d "${BUILD_DIR}" ;;
    *)             tar -xf "${DEST_FILE}" -C "${BUILD_DIR}" ;;
esac

# --- 5. 核心：多级路径探测逻辑 (确保通用性) ---
log_info "Locating source root..."

# 优先级 1: 检查是否直接解压到了 build 根目录 (Flat structure)
if [ -f "${BUILD_DIR}/CMakeLists.txt" ] || [ -f "${BUILD_DIR}/Makefile" ] || [ -f "${BUILD_DIR}/configure" ]; then
    REAL_SRC_PATH="${BUILD_DIR}"

# 优先级 2: 查找名字包含软件名的文件夹 (兼容你之前的所有项目)
elif find "${BUILD_DIR}" -maxdepth 1 -mindepth 1 -type d -iname "*${SOFT_NAME}*" | grep -q .; then
    REAL_SRC_PATH=$(find "${BUILD_DIR}" -maxdepth 1 -mindepth 1 -type d -iname "*${SOFT_NAME}*" | head -n 1)

# 优先级 3: 查找包含 project 关键字的顶级 CMakeLists.txt (解决 raxml-ng 问题)
elif find "${BUILD_DIR}" -maxdepth 2 -name "CMakeLists.txt" -exec grep -l "project" {} + | grep -q .; then
    REAL_SRC_PATH=$(find "${BUILD_DIR}" -maxdepth 2 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)

# 优先级 4: 最后的兜底，取 build 下产生的第一个文件夹
else
    REAL_SRC_PATH=$(find "${BUILD_DIR}" -maxdepth 1 -mindepth 1 -type d | head -n 1)
fi

# 6. 最终检查与绝对路径转换
if [ -z "$REAL_SRC_PATH" ] || [ ! -d "$REAL_SRC_PATH" ]; then
    log_err "Failed to locate any valid source directory."
    exit 1
fi

REAL_SRC_PATH=$(cd "$REAL_SRC_PATH" && pwd)
echo "SRC_PATH=${REAL_SRC_PATH}" > build_env.txt
log_info "Source ready at: ${REAL_SRC_PATH}"
