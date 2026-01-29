#!/bin/bash
# 通用产物上传脚本 - 对接config/artifact.env，标准化产物命名+生成校验和+上传GitHub Artifacts
# 入参：$1=软件名 $2=版本号 $3=原始产物文件路径（编译脚本输出的文件）
# 输出：标准化后的产物文件路径（供CI上传）

# 脚本根目录
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source $SCRIPT_DIR/utils.sh
source $SCRIPT_DIR/../config/global.env
source $SCRIPT_DIR/../config/platform.env
source $SCRIPT_DIR/../config/artifact.env

# 入参校验
check_param "软件名" $1
check_param "版本号" $2
check_param "原始产物路径" $3
export SOFT_NAME=$1
export SOFT_VERSION=$2
export ORIGIN_ARTIFACT=$(normalize_path $3)
check_param "标准化原始产物路径" $ORIGIN_ARTIFACT

# 核心变量
export PLATFORM=$(get_platform)
export ARCH=$(get_arch)
export WINDOWS_SUFFIX=""
# Windows添加.exe后缀
if [[ $PLATFORM == "windows" ]]; then
    export WINDOWS_SUFFIX=$WINDOWS_EXE_SUFFIX
fi

# ==================== 步骤1：标准化产物命名 ====================
# 替换命名模板中的变量：{soft}/{ver}/{os}/{arch}/{suffix}
export ARTIFACT_NAME=$(echo $ARTIFACT_NAME_PATTERN | \
    sed "s/{soft}/$SOFT_NAME/g" | \
    sed "s/{ver}/$SOFT_VERSION/g" | \
    sed "s/{os}/$PLATFORM/g" | \
    sed "s/{arch}/$ARCH/g" | \
    sed "s/{suffix}/$WINDOWS_SUFFIX/g")
# 标准化产物路径（仓库根目录）
export ARTIFACT_FILE="$ARTIFACT_UPLOAD_PATH/$ARTIFACT_NAME"
# 复制原始产物到标准化路径
cp -f $ORIGIN_ARTIFACT $ARTIFACT_FILE || { ERROR "产物重命名失败：$ORIGIN_ARTIFACT -> $ARTIFACT_FILE"; exit 1; }
INFO "步骤1完成：产物标准化命名 | 原始：$ORIGIN_ARTIFACT | 标准化：$ARTIFACT_FILE"

# ==================== 步骤2：生成产物校验和（GENERATE_CHECKSUM=true） ====================
if [[ $GENERATE_CHECKSUM == "true" ]]; then
    INFO "步骤2开始：生成产物校验和（MD5/SHA256）"
    # MD5
    export MD5_FILE=$(echo $CHECKSUM_MD5_PATTERN | sed "s/{artifact_name}/$ARTIFACT_NAME/g")
    md5sum $ARTIFACT_FILE > $MD5_FILE || { ERROR "生成MD5失败"; exit 1; }
    # SHA256
    export SHA256_FILE=$(echo $CHECKSUM_SHA256_PATTERN | sed "s/{artifact_name}/$ARTIFACT_NAME/g")
    sha256sum $ARTIFACT_FILE > $SHA256_FILE || { ERROR "生成SHA256失败"; exit 1; }
    INFO "步骤2完成：生成校验和 | MD5：$MD5_FILE | SHA256：$SHA256_FILE"
    # 待上传文件列表（产物+校验和）
    export UPLOAD_FILES="$ARTIFACT_FILE $MD5_FILE $SHA256_FILE"
else
    WARN "跳过步骤2：GENERATE_CHECKSUM=false"
    export UPLOAD_FILES="$ARTIFACT_FILE"
fi

# ==================== 步骤3：验证产物并输出上传路径（供GitHub Actions使用） ====================
# 调用验证脚本
source $SCRIPT_DIR/verify_build.sh $ARTIFACT_FILE || { ERROR "产物验证失败，无法上传"; exit 1; }
# 输出待上传文件路径（GitHub Actions通过echo ::set-output获取）
INFO "步骤3完成：产物验证通过，待上传文件：$UPLOAD_FILES"
# 写入环境变量，供CI读取
echo "ARTIFACT_NAME=$ARTIFACT_NAME" >> $GITHUB_ENV 2>/dev/null
echo "UPLOAD_FILES=$UPLOAD_FILES" >> $GITHUB_ENV 2>/dev/null
# 打印最终产物路径（核心，CI上传时使用）
echo $UPLOAD_FILES

SUCCESS "产物上传准备完成 | 标准化产物：$ARTIFACT_FILE"
