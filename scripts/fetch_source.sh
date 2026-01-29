#!/bin/bash
# 标准化拉取源码脚本
# 被build-cross.yml调用，传参：soft_name(软件名)、soft_version(版本号)
# 拉取源码到标准化source_cache目录，返回源码根目录（供工作流设置SOURCE_DIR）
# 个性化：按软件/版本修改拉取逻辑（git clone/wget/curl），返回值统一为源码根目录

set -e
log_info() { echo -e "\033[32m[SCRIPTS-FETCH-SOURCE] $1\033[0m"; }
log_error() { echo -e "\033[31m[SCRIPTS-FETCH-SOURCE] $1\033[0m"; exit 1; }

# 步骤1：验证传参（来自标准化工作流）
if [ $# -ne 2 ]; then log_error "传参错误！用法：$0 <soft_name> <soft_version>"; fi
SOFT_NAME="$1"
SOFT_VERSION="$2"
# 标准化源码缓存目录（工作流配置了缓存，所有软件复用）
SOURCE_CACHE="$GITHUB_WORKSPACE/source_cache/$SOFT_NAME/$SOFT_VERSION"
mkdir -p "$SOURCE_CACHE" || log_error "创建标准化源码缓存目录失败！"

# 步骤2：按软件/版本个性化拉取源码（仅此处需按软件修改，其他逻辑标准化）
log_info "拉取[$SOFT_NAME-$SOFT_VERSION]源码到标准化缓存：$SOURCE_CACHE"
case "$SOFT_NAME-$SOFT_VERSION" in
  "poplddecay-v3.43")
    # PopLDdecay v3.43 源码拉取逻辑（示例：git clone，可替换为wget解压）
    SRC_REPO="https://github.com/HeWM2008/PopLDdecay.git"  # 官方源码地址
    SRC_DIR="$SOURCE_CACHE/poplddecay"  # 源码根目录（与build.sh中SRC_DIR对齐）
    if [ ! -d "$SRC_DIR" ]; then
        git clone --depth 1 --branch v3.43 "$SRC_REPO" "$SRC_DIR" || log_error "PopLDdecay v3.43源码拉取失败！"
    else
        log_info "源码已存在，跳过拉取！"
    fi
    # 必须返回源码根目录（供工作流设置SOURCE_DIR）
    echo "$SRC_DIR"
    ;;
  # 其他软件/版本只需添加case分支，返回源码根目录即可，标准化逻辑不变
  # "othersoft-v1.0")
  #   SRC_REPO="https://xxx/othersoft.git"
  #   SRC_DIR="$SOURCE_CACHE/othersoft"
  #   git clone --depth 1 "$SRC_REPO" "$SRC_DIR"
  #   echo "$SRC_DIR"
  #   ;;
  *)
    log_error "未配置[$SOFT_NAME-$SOFT_VERSION]源码拉取逻辑！请修改$0";
    ;;
esac

log_info "✅ [$SOFT_NAME-$SOFT_VERSION]源码拉取完成！源码根目录：$SRC_DIR"
