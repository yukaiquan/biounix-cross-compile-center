#!/bin/bash
# 通用源码拉取脚本 - 按软件/版本拉取源码到source_cache
# 入参：$1=软件名 $2=版本号
# 输出：仅源码根目录绝对路径（stdout纯净化，日志走stderr）
# 修复：日志重定向到stderr，解决GITHUB_ENV写入格式错误

# 引入工具函数
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source ${SCRIPT_DIR}/utils.sh

# 重写日志函数：输出到stderr（>&2），不干扰stdout
log_info() {
    local TIME=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[INFO]  ${TIME} $1" >&2
}

log_error() {
    local TIME=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "\033[31m[ERROR]  ${TIME} $1\033[0m" >&2
    exit 1
}

# 检查入参
if [ $# -ne 2 ]; then
    log_error "入参错误！用法：$0 <软件名> <版本号>"
fi

SOFT_NAME=$1
SOFT_VERSION=$2
# 源码缓存目录（标准化）
SOURCE_CACHE="${SCRIPT_DIR}/../source_cache/${SOFT_NAME}/${SOFT_VERSION}"
check_dir ${SOURCE_CACHE}

# 加载软件专属源码配置
SOURCE_CONFIG="${SCRIPT_DIR}/../softwares/${SOFT_NAME}/${SOFT_VERSION}/source.env"
if [ ! -f "${SOURCE_CONFIG}" ]; then
    log_error "源码配置文件不存在：${SOURCE_CONFIG}"
fi
source ${SOURCE_CONFIG}
log_info "开始拉取源码 | 仓库：${GIT_REPO} | 版本：${GIT_TAG}"

# 拉取/更新源码（git克隆提示默认走stderr，无需额外处理）
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

# 关键：stdout仅输出纯源码目录路径，无任何其他内容
echo ${SOURCE_DIR}
exit 0
