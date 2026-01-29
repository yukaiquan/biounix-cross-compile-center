#!/bin/bash
# 通用源码拉取脚本 - 按软件/版本拉取源码到source_cache
# 入参：$1=软件名 $2=版本号
# 输出：源码根目录绝对路径
# 修复：用兼容的realpath、确保路径正确

# 引入工具函数
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source ${SCRIPT_DIR}/utils.sh

# 检查入参
if [ $# -ne 2 ]; then
    log_error "入参错误！用法：$0 <软件名> <版本号>"
fi

SOFT_NAME=$1
SOFT_VERSION=$2
# 源码缓存目录（标准化）
SOURCE_CACHE="${SCRIPT_DIR}/../source_cache/${SOFT_NAME}/${SOFT_VERSION}"
check_dir ${SOURCE_CACHE}

# 加载软件专属源码配置（softwares/软件/版本/source.env）
SOURCE_CONFIG="${SCRIPT_DIR}/../softwares/${SOFT_NAME}/${SOFT_VERSION}/source.env"
if [ ! -f "${SOURCE_CONFIG}" ]; then
    log_error "源码配置文件不存在：${SOURCE_CONFIG}"
fi
source ${SOURCE_CONFIG}
log_info "开始拉取源码 | 仓库：${GIT_REPO} | 版本：${GIT_TAG}"

# 拉取/更新源码
if [ ! -d "${SOURCE_CACHE}/${SOFT_NAME}" ]; then
    # 首次拉取：克隆指定标签
    git clone --depth 1 --branch ${GIT_TAG} ${GIT_REPO} ${SOURCE_CACHE}/${SOFT_NAME} || log_error "git克隆失败"
else
    # 已存在：更新源码
    cd ${SOURCE_CACHE}/${SOFT_NAME}
    git fetch --depth 1 origin ${GIT_TAG}
    git checkout ${GIT_TAG} || log_error "git切换版本失败"
fi

# 获取源码根目录绝对路径（兼容realpath）
SOURCE_DIR=$(realpath_compat "${SOURCE_CACHE}/${SOFT_NAME}")
log_info "源码拉取完成 | 源码根目录：${SOURCE_DIR}"

# 输出源码根目录（供上层脚本获取）
echo ${SOURCE_DIR}
exit 0
