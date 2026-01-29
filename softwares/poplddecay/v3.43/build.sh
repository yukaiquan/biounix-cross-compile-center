#!/bin/bash
# PopLDdecay v3.43 专属编译脚本
# 编译细节全个性化：跨平台适配、编译器选择、参数配置
# 被标准化工作流build-cross.yml调用，自动接收工作流传递的环境变量
# 环境变量来自工作流：SOURCE_DIR(源码根目录)、PLATFORM(linux/macos/windows)、ARCH(x64)、BUILD_OUTPUT_DIR(标准化产物目录)
# 配置参数来自本目录config.env：OUTPUT_NAME、COMPILE_OPT、SRC_DIR、MAIN_SRC、LIBS

set -e  # 执行出错立即退出，符合标准化流程的错误处理
# 日志函数（与标准化脚本日志风格统一）
log_info() { echo -e "\033[32m[POPLDDECAY-V3.43] $1\033[0m"; }
log_error() { echo -e "\033[31m[POPLDDECAY-V3.43] $1\033[0m"; exit 1; }

# 步骤1：验证工作流传递的环境变量（确保标准化流程正常）
log_info "验证标准化工作流环境变量"
if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then log_error "SOURCE_DIR未设置或不存在！"; fi
if [ -z "$PLATFORM" ] || [[ ! "$PLATFORM" =~ ^(linux|macos|windows)$ ]]; then log_error "PLATFORM未设置或非法！仅支持linux/macos/windows"; fi
if [ -z "$ARCH" ]; then log_error "ARCH未设置！"; fi
if [ -z "$BUILD_OUTPUT_DIR" ]; then log_error "BUILD_OUTPUT_DIR未设置！"; fi
# 创建标准化产物目录（确保存在）
mkdir -p "$BUILD_OUTPUT_DIR" || log_error "创建标准化产物目录失败！"

# 步骤2：拼接核心路径（个性化，基于源码根目录）
SRC_FILE="$SOURCE_DIR/$SRC_DIR/$MAIN_SRC"  # 核心源文件完整路径
MAKEFILE="$SOURCE_DIR/Makefile"            # 动态生成的跨平台Makefile路径
log_info "核心路径：源码文件=$SRC_FILE，Makefile=$MAKEFILE，标准化产物目录=$BUILD_OUTPUT_DIR"
# 验证核心源文件（确保源码拉取成功）
if [ ! -f "$SRC_FILE" ]; then log_error "核心源文件不存在！请检查源码拉取脚本fetch_source.sh"; fi

# 步骤3：跨平台编译参数个性化配置（核心，按PLATFORM适配）
log_info "开始跨平台编译参数配置：PLATFORM=$PLATFORM，ARCH=$ARCH"
TARGET=""          # 最终编译产物名（带exe后缀/无）
CXX=""             # 编译器
CXXFLAGS="-O$COMPILE_OPT"  # 基础编译参数（来自config.env）
LDFLAGS=""         # 链接参数
case "$PLATFORM" in
  "linux")
    # Linux：纯静态编译，无exe后缀，系统默认g++
    TARGET="$OUTPUT_NAME"
    CXX="g++"
    CXXFLAGS+=" -static"
    LDFLAGS="-static"
    log_info "Linux配置：纯静态编译，编译器=$CXX，参数=$CXXFLAGS $LDFLAGS，产物=$TARGET"
    ;;
  "macos")
    # macOS：动态编译（适配系统限制），自动找brew带版本GCC，无exe后缀
    TARGET="$OUTPUT_NAME"
    # 优先找brew最新GCC（g++-14 → g++-13 → 系统g++），避开Clang
    CXX=$(which g++-14 || which g++-13 || which g++)
    if [ -z "$CXX" ] || [ ! -x "$CXX" ]; then log_error "macOS未找到可用的g++！请检查依赖安装"; fi
    # 移除-static，适配macOS系统库限制，仅保留优化参数
    LDFLAGS=""
    log_info "macOS配置：动态编译，编译器=$CXX，参数=$CXXFLAGS $LDFLAGS，产物=$TARGET"
    ;;
  "windows")
    # Windows-MSYS2：纯静态编译，带exe后缀，MSYS2默认g++
    TARGET="$OUTPUT_NAME.exe"
    CXX="g++"
    CXXFLAGS+=" -static"
    LDFLAGS="-static"
    log_info "Windows配置：纯静态编译，编译器=$CXX，参数=$CXXFLAGS $LDFLAGS，产物=$TARGET"
    ;;
esac

# 步骤4：动态生成跨平台Makefile（个性化，无需手动维护）
log_info "动态生成跨平台Makefile：$MAKEFILE"
cat > "$MAKEFILE" << EOF
# 动态生成的PopLDdecay v3.43 Makefile（$PLATFORM-$ARCH）
# 由专属编译脚本build.sh生成，编译细节全个性化
TARGET = $TARGET
SRC = $SRC_DIR/$MAIN_SRC
LIBS = $LIBS
CXX = $CXX
CXXFLAGS = $CXXFLAGS
LDFLAGS = $LDFLAGS

all: \$(TARGET)
	@echo "✅ 编译成功：\$(TARGET)"

\$(TARGET): \$(SRC)
	\$(CXX) \$(CXXFLAGS) \$(LDFLAGS) -o \$@ \$< \$(LIBS)

clean:
	rm -rf \$(TARGET) *.o
EOF

# 步骤5：执行编译（个性化编译逻辑，仅本软件/版本生效）
log_info "进入源码根目录执行编译：$SOURCE_DIR"
cd "$SOURCE_DIR" || log_error "进入源码根目录失败！"
# 执行make编译（动态生成的Makefile）
make clean || log_info "清理旧产物（首次编译可忽略）"
make || log_error "编译失败！请查看日志"
# 验证编译产物（确保生成成功）
if [ ! -f "$TARGET" ]; then log_error "编译产物未生成！"; fi
log_info "编译成功，产物：$SOURCE_DIR/$TARGET"

# 步骤6：将产物复制到标准化产物目录（对接标准化工作流）
log_info "将产物复制到标准化目录：$BUILD_OUTPUT_DIR/"
cp -f "$TARGET" "$BUILD_OUTPUT_DIR/" || log_error "复制产物到标准化目录失败！"
# 验证标准化产物（确保对接成功）
STANDARD_TARGET="$BUILD_OUTPUT_DIR/$TARGET"
if [ ! -f "$STANDARD_TARGET" ]; then log_error "标准化产物不存在！"; fi
log_info "✅ PopLDdecay v3.43 编译完成！标准化产物路径：$STANDARD_TARGET"

# 步骤7：清理源码目录临时文件（符合标准化流程的整洁要求）
make clean || log_info "清理源码目录临时文件"
log_info "✅ PopLDdecay v3.43 专属编译脚本执行完成，已对接标准化工作流！"
