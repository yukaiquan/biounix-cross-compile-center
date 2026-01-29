#!/bin/bash
# 通用产物上传脚本 - 标准化产物名+输出待上传文件路径
# 入参：$1=软件名 $2=版本号 $3=产物源目录
# 输出：待上传的产物文件绝对路径（stdout纯净化）
set -e

# 核心修复：引入通用工具函数脚本（解决所有函数未找到问题）
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source ${SCRIPT_DIR}/utils.sh

# 入参检查（调用utils里的check_param）
SOFT_NAME=$1
SOFT_VERSION=$2
ORIGIN_DIR=$3
check_param "软件名" ${SOFT_NAME}
check_param "版本号" ${SOFT_VERSION}
check_param "产物源目录" ${ORIGIN_DIR}

# 路径标准化（调用utils里的normalize_path）
SRC_DIR=$(normalize_path ${ORIGIN_DIR})
check_param "标准化后产物目录" ${SRC_DIR}

# 检查源目录是否存在
if [ ! -d ${SRC_DIR} ]; then
    log_error "产物源目录不存在：${SRC_DIR}"
fi

# 获取平台/架构（调用utils里的get_platform/get_arch，已做别名兼容）
PLATFORM=$(get_platform)
ARCH=$(get_arch)

# 生成标准化产物名（调用utils里的get_artifact_name）
ARTIFACT_NAME=$(get_artifact_name ${SOFT_NAME} ${SOFT_VERSION} ${PLATFORM} ${ARCH})
# 产物目标路径（当前工作目录，方便GitHub Actions上传）
DEST_FILE=$(normalize_path "./${ARTIFACT_NAME}")

# 核心：复制产物到目标路径（兼容Windows，处理exe后缀）
if [ ${PLATFORM} == "windows" ]; then
    # Windows产物加.exe后缀
    SRC_FILE=$(ls ${SRC_DIR}/*.exe | head -1)
    check_param "Windows产物文件" ${SRC_FILE}
    cp -f ${SRC_FILE} ${DEST_FILE}.exe || log_error "复制Windows产物失败"
    FINAL_FILE=$(normalize_path "${DEST_FILE}.exe")
else
    # Linux/macOS直接复制二进制
    SRC_FILE=$(ls ${SRC_DIR}/* | grep -v "\.sh" | grep -v "\.env" | head -1)
    check_param "Linux/macOS产物文件" ${SRC_FILE}
    cp -f ${SRC_FILE} ${DEST_FILE} || log_error "复制Linux/macOS产物失败"
    FINAL_FILE=${DEST_FILE}
fi

# 验证产物是否存在
if [ ! -f ${FINAL_FILE} ]; then
    log_error "产物文件生成失败：${FINAL_FILE}"
fi

log_info "产物标准化完成 | 源文件：${SRC_FILE} | 目标文件：${FINAL_FILE}"
# 关键：stdout仅输出待上传文件路径，供GitHub Actions获取
echo ${FINAL_FILE}
exit 0
