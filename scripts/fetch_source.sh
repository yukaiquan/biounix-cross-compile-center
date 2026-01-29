#!/bin/bash
# 通用源码拉取脚本 - 对接softwares/[软件]/[版本]/config.env的SOURCE_*参数
# 支持：git clone（指定分支/标签/提交ID）、zip/tar.gz/tar.bz2（下载解压）
# 入参：$1=软件名 $2=版本号
# 输出：源码根目录路径（写入SOURCE_DIR环境变量）

# 脚本根目录（定位到scripts/，方便引入其他脚本）
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
# 引入工具函数
source $SCRIPT_DIR/utils.sh
# 引入全局配置
source $SCRIPT_DIR/../config/global.env
source $SCRIPT_DIR/../config/platform.env

# 入参校验
check_param "软件名" $1
check_param "版本号" $2
export SOFT_NAME=$1
export SOFT_VERSION=$2

# 软件版本配置文件路径
export SOFT_CONFIG="$SCRIPT_DIR/../softwares/$SOFT_NAME/$SOFT_VERSION/config.env"
check_param "软件版本配置文件" $SOFT_CONFIG
if [[ ! -f $SOFT_CONFIG ]]; then
    ERROR "配置文件不存在：$SOFT_CONFIG"
    exit 1
fi
# 引入软件版本配置
source $SOFT_CONFIG

# 核心参数校验（SOURCE_*）
check_param "源码类型(SOURCE_TYPE)" $SOURCE_TYPE
check_param "源码地址(SOURCE_URL)" $SOURCE_URL
# 源码类型限制（git/zip/tar/tar.gz/tar.bz2）
if [[ ! $SOURCE_TYPE =~ ^(git|zip|tar|tar.gz|tar.bz2)$ ]]; then
    ERROR "不支持的源码类型：$SOURCE_TYPE，仅支持git/zip/tar/tar.gz/tar.bz2"
    exit 1
fi

# 初始化目录
create_dir $SOURCE_CACHE_DIR
# 源码缓存子目录（按软件/版本划分，避免冲突）
export SOURCE_CACHE_SUBDIR="$SOURCE_CACHE_DIR/$SOFT_NAME/$SOFT_VERSION"
create_dir $SOURCE_CACHE_SUBDIR

# ==================== 核心拉取逻辑 ====================
INFO "开始拉取源码 | 软件：$SOFT_NAME | 版本：$SOFT_VERSION | 类型：$SOURCE_TYPE | 地址：$SOURCE_URL"
case $SOURCE_TYPE in
    # Git拉取（支持指定分支/标签/提交ID：SOURCE_CHECKOUT）
    git)
        export GIT_REPO_NAME=$(basename $SOURCE_URL .git)
        export SOURCE_DIR="$SOURCE_CACHE_SUBDIR/$GIT_REPO_NAME"
        # 若已缓存，更新源码；否则克隆
        if [[ -d $SOURCE_DIR/.git ]]; then
            INFO "源码已缓存，执行git pull更新"
            cd $SOURCE_DIR && git pull || { ERROR "git pull失败"; exit 1; }
        else
            INFO "克隆源码仓库：$SOURCE_URL"
            git clone $SOURCE_URL $SOURCE_DIR || { ERROR "git clone失败"; exit 1; }
        fi
        # 切换到指定分支/标签/提交ID
        if [[ -n $SOURCE_CHECKOUT ]]; then
            INFO "切换源码到：$SOURCE_CHECKOUT"
            cd $SOURCE_DIR && git checkout $SOURCE_CHECKOUT || { ERROR "git checkout失败"; exit 1; }
        fi
        ;;
    # Zip/Tar解压（支持zip/tar/tar.gz/tar.bz2）
    zip|tar|tar.gz|tar.bz2)
        # 下载文件名（从URL提取，或自定义）
        export SOURCE_FILE="$SOURCE_CACHE_SUBDIR/$(basename $SOURCE_URL)"
        # 若未缓存，下载源码
        if [[ ! -f $SOURCE_FILE ]]; then
            INFO "下载源码文件：$SOURCE_URL -> $SOURCE_FILE"
            # 优先用wget，无则用curl
            if command -v wget &> /dev/null; then
                wget -O $SOURCE_FILE $SOURCE_URL || { ERROR "wget下载失败"; exit 1; }
            else
                curl -L -o $SOURCE_FILE $SOURCE_URL || { ERROR "curl下载失败"; exit 1; }
            fi
        else
            INFO "源码文件已缓存：$SOURCE_FILE"
        fi
        # 解压目录
        export SOURCE_DIR="$SOURCE_CACHE_SUBDIR/unpack"
        create_dir $SOURCE_DIR && rm -rf $SOURCE_DIR/*
        INFO "解压源码文件：$SOURCE_FILE -> $SOURCE_DIR"
        # 按类型解压
        case $SOURCE_TYPE in
            zip) unzip -q $SOURCE_FILE -d $SOURCE_DIR || { ERROR "unzip解压失败"; exit 1; } ;;
            tar) tar -xf $SOURCE_FILE -C $SOURCE_DIR || { ERROR "tar解压失败"; exit 1; } ;;
            tar.gz) tar -zxf $SOURCE_FILE -C $SOURCE_DIR || { ERROR "tar.gz解压失败"; exit 1; } ;;
            tar.bz2) tar -jxf $SOURCE_FILE -C $SOURCE_DIR || { ERROR "tar.bz2解压失败"; exit 1; } ;;
        esac
        # 处理解压后单层目录（如xxx-v1.0/下是源码，自动进入）
        local UNPACK_SUBDIRS=$(ls -l $SOURCE_DIR | grep '^d' | wc -l)
        if [[ $UNPACK_SUBDIRS -eq 1 ]]; then
            export SOURCE_DIR="$SOURCE_DIR/$(ls $SOURCE_DIR)"
            INFO "解压后为单层目录，自动进入：$SOURCE_DIR"
        fi
        ;;
esac

# 校验源码目录是否存在
SOURCE_DIR=$(normalize_path $SOURCE_DIR)
check_param "源码根目录" $SOURCE_DIR
if [[ ! -d $SOURCE_DIR ]]; then
    ERROR "源码拉取失败，源码目录不存在：$SOURCE_DIR"
    exit 1
fi

# 输出源码目录（供后续编译脚本使用）
export SOURCE_DIR
SUCCESS "源码拉取完成 | 源码根目录：$SOURCE_DIR"
echo $SOURCE_DIR
