#!/bin/bash
# 通用产物验证脚本 - 对接softwares/[软件]/[版本]/config.env的VERIFY_*参数
# 验证项：1. 产物是否存在 2. 是否为纯静态（VERIFY_STATIC=true） 3. 能否正常运行（VERIFY_RUN=true）
# 入参：$1=产物文件路径（全路径）
# 配置：VERIFY_STATIC/VERIFY_RUN 从软件版本config.env读取

# 脚本根目录
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source $SCRIPT_DIR/utils.sh
source $SCRIPT_DIR/../config/global.env
source $SCRIPT_DIR/../config/platform.env

# 入参校验
check_param "产物文件路径" $1
export ARTIFACT_FILE=$(normalize_path $1)
check_param "标准化产物路径" $ARTIFACT_FILE

# 从产物路径提取软件/版本（用于加载配置）
# 产物名规范：{soft}-{ver}-{os}-{arch}{suffix}
export SOFT_NAME=$(echo $(basename $ARTIFACT_FILE) | cut -d'-' -f1)
export SOFT_VERSION=$(echo $(basename $ARTIFACT_FILE) | cut -d'-' -f2)
check_param "从产物名提取的软件名" $SOFT_NAME
check_param "从产物名提取的版本号" $SOFT_VERSION

# 引入软件版本配置
export SOFT_CONFIG="$SCRIPT_DIR/../softwares/$SOFT_NAME/$SOFT_VERSION/config.env"
check_param "软件版本配置文件" $SOFT_CONFIG
source $SOFT_CONFIG

# 识别平台/架构
export PLATFORM=$(get_platform)
export ARCH=$(get_arch)
INFO "开始验证产物 | 软件：$SOFT_NAME | 版本：$SOFT_VERSION | 产物：$ARTIFACT_FILE | 平台：$PLATFORM-$ARCH"

# ==================== 验证1：产物是否存在且有执行权限 ====================
if [[ ! -f $ARTIFACT_FILE ]]; then
    ERROR "产物文件不存在：$ARTIFACT_FILE"
    exit 1
fi
# 添加执行权限
chmod +x $ARTIFACT_FILE || { ERROR "为产物添加执行权限失败"; exit 1; }
INFO "验证1通过：产物存在且已添加执行权限"

# ==================== 验证2：是否为纯静态二进制（VERIFY_STATIC=true） ====================
if [[ $VERIFY_STATIC == "true" ]]; then
    INFO "开始验证2：纯静态二进制检查"
    case $PLATFORM in
        # Linux：ldd命令检查，非动态可执行文件即为纯静态
        linux)
            local LDD_RESULT=$(ldd $ARTIFACT_FILE 2>&1)
            if [[ $LDD_RESULT =~ "not a dynamic executable" ]]; then
                INFO "验证2通过：Linux纯静态二进制"
            else
                ERROR "验证2失败：非纯静态二进制，ldd结果：$LDD_RESULT"
                exit 1
            fi
            ;;
        # Windows/macOS：file命令检查静态链接标识
        windows|macos)
            local FILE_RESULT=$(file $ARTIFACT_FILE 2>&1)
            if [[ $FILE_RESULT =~ "statically linked" || $FILE_RESULT =~ "MSYS2 static" ]]; then
                INFO "验证2通过：$PLATFORM纯静态二进制"
            else
                WARN "验证2警告：$PLATFORM无标准静态检查命令，file结果：$FILE_RESULT"
                # Windows/macOS不强制失败，仅警告
            fi
            ;;
    esac
else
    WARN "跳过验证2：VERIFY_STATIC=false"
fi

# ==================== 验证3：产物能否正常运行（VERIFY_RUN=true） ====================
if [[ $VERIFY_RUN == "true" ]]; then
    INFO "开始验证3：产物运行性检查（执行--help/-h）"
    # 尝试执行--help或-h，只要不返回非0即认为可运行
    if $ARTIFACT_FILE --help >/dev/null 2>&1 || $ARTIFACT_FILE -h >/dev/null 2>&1; then
        INFO "验证3通过：产物能正常运行并输出帮助信息"
    else
        # 部分软件无--help/-h，尝试直接执行（短时间退出）
        $ARTIFACT_FILE >/dev/null 2>&1 &
        local PID=$!
        sleep 2
        # 检查进程是否存在，不存在则认为正常退出
        if ps -p $PID >/dev/null 2>&1; then
            kill $PID >/dev/null 2>&1
            ERROR "验证3失败：产物运行后无响应，PID：$PID"
            exit 1
        else
            INFO "验证3通过：产物能正常执行并退出"
        fi
    fi
else
    WARN "跳过验证3：VERIFY_RUN=false"
fi

# 所有验证完成
SUCCESS "产物验证全部完成（含跳过项）| 产物：$ARTIFACT_FILE"
