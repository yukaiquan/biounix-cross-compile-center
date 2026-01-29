#!/bin/bash
# 标准化产物上传脚本
# 被build-cross.yml调用，传参：soft_name(软件名)、soft_version(版本号)、origin_artifact(原始产物路径)
# 标准化产物名：soft_name-soft_version-platform-arch[.exe]
# 返回待上传文件的完整路径，供工作流调用upload-artifact动作

set -e
log_info() { echo -e "\033[32m[SCRIPTS-UPLOAD-ARTIFACT] $1\033[0m"; }
log_error() { echo -e "\033[31m[SCRIPTS-UPLOAD-ARTIFACT] $1\033[0m"; exit 1; }

# 步骤1：验证传参（来自标准化工作流）
if [ $# -ne 3 ]; then log_error "传参错误！用法：$0 <soft_name> <soft_version> <origin_artifact>"; fi
SOFT_NAME="$1"
SOFT_VERSION="$2"
ORIGIN_ARTIFACT="$3"
# 验证原始产物
if [ ! -f "$ORIGIN_ARTIFACT" ]; then log_error "原始产物不存在！$ORIGIN_ARTIFACT"; fi

# 步骤2：获取工作流环境变量（平台/架构）
if [ -z "$PLATFORM" ] || [ -z "$ARCH" ]; then log_error "PLATFORM/ARCH未设置！请检查标准化工作流"; fi

# 步骤3：标准化产物名（与工作流ARTIFACT_NAME对齐）
STANDARD_NAME="$SOFT_NAME-$SOFT_VERSION-$PLATFORM-$ARCH"
# Windows添加exe后缀
if [ "$PLATFORM" == "windows" ]; then STANDARD_NAME+=".exe"; fi
# 标准化产物完整路径
STANDARD_ARTIFACT="$BUILD_OUTPUT_DIR/$STANDARD_NAME"
# 重命名产物（标准化）
cp -f "$ORIGIN_ARTIFACT" "$STANDARD_ARTIFACT" || log_error "产物标准化重命名失败！"
log_info "产物标准化完成：$STANDARD_ARTIFACT"

# 步骤4：返回待上传文件路径（供工作流调用）
echo "$STANDARD_ARTIFACT"
log_info "✅ 产物上传脚本执行完成，待上传文件：$STANDARD_ARTIFACT"
