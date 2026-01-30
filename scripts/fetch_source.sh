#!/bin/bash
set -e

# --- 1. 加载工具函数和全局配置 ---
# 无论从哪里调用，都尝试加载 utils.sh
if [ -f "scripts/utils.sh" ]; then
    source scripts/utils.sh
else
    log_info() { echo -e "\033[32m[INFO]\033[0m $1"; }
    log_err()  { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }
fi

# 加载全局路径定义
if [ -f "config/global.env" ]; then
    source config/global.env
fi

# --- 2. 接收参数 ---
SOFT_NAME=$1
SOFT_VER=$2

if [ -z "$SOFT_NAME" ] || [ -z "$SOFT_VER" ]; then
    log_err "Usage: $0 <software_name> <version>"
fi

# --- 3. 加载软件特定配置 ---
SOFT_ENV="softwares/${SOFT_NAME}/${SOFT_VER}/source.env"
if [ -f "$SOFT_ENV" ]; then
    source "$SOFT_ENV"
else
    log_err "$SOFT_ENV not found"
fi

# --- 4. 准备目录 (核心修复：确保 build 目录纯净) ---
SOURCE_DIR=${SOURCE_DIR:-"./sources"}
BUILD_DIR=${BUILD_DIR:-"./build"}

mkdir -p "${SOURCE_DIR}"
# 解压前必须删除旧的构建目录，防止 find 命令匹配到上一个软件的源码
rm -rf "${BUILD_DIR}" && mkdir -p "${BUILD_DIR}"

# --- 5. 下载逻辑 ---
FILENAME=$(basename "${SOURCE_URL}")
DEST_FILE="${SOURCE_DIR}/${FILENAME}"

log_info "Downloading ${SOFT_NAME} ${SOFT_VER}..."
if [ ! -f "${DEST_FILE}" ]; then
    curl -L "${SOURCE_URL}" -o "${DEST_FILE}"
else
    log_info "Archive already exists, skipping download."
fi

# --- 6. 解压逻辑 (增加兼容性参数) ---
log_info "Extracting ${FILENAME}..."
case "${FILENAME}" in
    *.tar.gz|*.tgz)
        tar -zxf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
    *.tar.bz2)
        tar -jxf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
    *.zip)
        # -q: 静默, -o: 强制覆盖(无需交互)
        unzip -qo "${DEST_FILE}" -d "${BUILD_DIR}"
        ;;
    *)
        log_info "Attempting generic extraction..."
        tar -xf "${DEST_FILE}" -C "${BUILD_DIR}"
        ;;
esac

# --- 7. 定位解压后的源码目录 (核心修复) ---
# 策略：不按名字匹配，直接找 BUILD_DIR 下新产生的第一个文件夹
log_info "Locating source root..."
# 查找 build 目录下深度为 1 的第一个目录，排除 build 目录本身
REAL_SRC_PATH=$(find "${BUILD_DIR}" -maxdepth 1 -mindepth 1 -type d | head -n 1)

# 如果解压出来没有目录（文件直接平铺在 build 里），则源码根目录就是 build
if [ -z "$REAL_SRC_PATH" ]; then
    REAL_SRC_PATH="${BUILD_DIR}"
fi

# 关键：转换为绝对路径，规避 Windows 下所有 cd 命令的路径问题
REAL_SRC_PATH=$(cd "$REAL_SRC_PATH" && pwd)

# 写入 build_env.txt 供 GitHub Actions 的 $GITHUB_ENV 使用
echo "SRC_PATH=${REAL_SRC_PATH}" > build_env.txt

log_info "Source successfully prepared at: ${REAL_SRC_PATH}"
