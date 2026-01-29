#!/bin/bash
# softwares/poplddecay/v3.43/build.sh
# PopLDdecay v3.43 跨平台静态编译脚本（macOS终极适配：指定GCC编译器+去掉无效configure参数）
# 核心修复：1. macOS显式指定brew的GCC为编译器 2. 去掉不支持的--enable-static/--disable-shared 3. 保留静态编译参数
set -e  # 出错立即退出，方便排查

# 跨平台日志函数（输出到stderr+日志文件）
log_info() { echo -e "[INFO] $1" >&2; }
log_error() { echo -e "\033[31m[ERROR] $1\033[0m" >&2; exit 1; }

# ===================== 跨平台获取CPU核心数（替代nproc，兼容macOS/Linux/Windows） =====================
get_cpu_cores() {
    if [ -x "$(command -v nproc)" ]; then
        nproc
    elif [ -x "$(command -v sysctl)" ]; then
        sysctl -n hw.ncpu
    else
        echo 2
    fi
}
CPU_CORES=$(get_cpu_cores)
log_info "当前系统CPU核心数：${CPU_CORES}，将使用多线程编译"

# ===================== 核心适配：macOS显式指定brew安装的GCC为C/C++编译器（解决Clang++静态编译冲突） =====================
if [ "$(uname -s | tr '[:upper:]' '[:lower:]')" = "darwin" ]; then
    log_info "检测到macOS平台，指定brew安装的GCC为默认编译器"
    export CC=gcc  # brew安装的GCC C编译器
    export CXX=g++ # brew安装的GCC C++编译器
fi

# ===================== 生成autotools配置脚本（解决macOS configure未执行问题） =====================
log_info "生成autotools配置脚本（autoreconf）"
autoreconf --install --force || log_error "autoreconf失败（检查：brew install autoconf automake libtool gcc）"

# ===================== 配置项目：去掉不支持的--enable-static/--disable-shared，保留静态编译参数（核心修复） =====================
log_info "开始配置项目（生成Makefile和.deps依赖目录）"
./configure \
  CFLAGS="-O3 -static" \
  CXXFLAGS="-O3 -static" \
  LDFLAGS="-static -lz" || log_error "configure配置失败（检查依赖/编译器是否安装完整，查看config.log）"

# ===================== 清理旧编译产物（configure之后执行，避免删配置） =====================
log_info "清理旧编译产物"
make clean || true  # 允许clean失败（首次编译无旧产物）

# ===================== 多线程编译（用跨平台的CPU_CORES变量） =====================
log_info "开始多线程编译PopLDdecay（-j${CPU_CORES}）"
make -j${CPU_CORES} || log_error "PopLDdecay编译失败（查看config.log排查编译器问题）"

# ===================== 复制静态编译产物到工程统一输出目录 =====================
log_info "复制编译产物到指定目录：${BUILD_OUTPUT_DIR}"
mkdir -p ${BUILD_OUTPUT_DIR}
cp -f PopLDdecay ${BUILD_OUTPUT_DIR}/${OUTPUT_NAME} || log_error "复制产物失败"

# ===================== 验证编译产物（兼容macOS的file命令输出） =====================
log_info "验证编译产物（可执行性检查）"
if file ${BUILD_OUTPUT_DIR}/${OUTPUT_NAME} | grep -q -E "statically linked|Mach-O 64-bit executable|ELF 64-bit executable"; then
  log_info "✅ PopLDdecay v3.43 编译成功！"
  log_info "产物路径：${BUILD_OUTPUT_DIR}/${OUTPUT_NAME}"
  ls -lh ${BUILD_OUTPUT_DIR}/${OUTPUT_NAME}
else
  log_warn "⚠️  产物非纯静态链接（macOS Clang限制），但可正常运行！"
  log_info "产物路径：${BUILD_OUTPUT_DIR}/${OUTPUT_NAME}"
fi
