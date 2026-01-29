#!/bin/bash
# softwares/poplddecay/v3.43/build.sh
# PopLDdecay v3.43 跨平台静态编译脚本（终极兼容：Linux/macOS/Windows-MSYS2）
# 修复：macOS加autoreconf生成configure + 跨平台CPU核心数适配（替代nproc）
set -e  # 出错立即退出，方便排查

# 跨平台日志函数（输出到stderr，不干扰stdout）
log_info() { echo -e "[INFO] $1" >&2; }
log_error() { echo -e "\033[31m[ERROR] $1\033[0m" >&2; exit 1; }

# ===================== 核心修复1：跨平台获取CPU核心数（替代nproc，兼容macOS/Linux/Windows） =====================
get_cpu_cores() {
    if [ -x "$(command -v nproc)" ]; then
        # Linux：用nproc
        nproc
    elif [ -x "$(command -v sysctl)" ]; then
        # macOS：用sysctl
        sysctl -n hw.ncpu
    else
        # Windows/MSYS2或其他环境：默认用2核心
        echo 2
    fi
}
CPU_CORES=$(get_cpu_cores)
log_info "当前系统CPU核心数：${CPU_CORES}，将使用多线程编译"

# ===================== 核心修复2：加autoreconf生成可执行configure（解决macOS configure未执行问题） =====================
log_info "生成autotools配置脚本（autoreconf）"
autoreconf --install --force || log_error "autoreconf失败（检查autotools是否安装：brew install autoconf automake libtool）"

# ===================== 步骤3：执行configure生成完整Makefile和.deps目录 =====================
log_info "开始配置项目（生成Makefile和.deps依赖目录）"
./configure \
  --enable-static \
  --disable-shared \
  CFLAGS="-O3 -static" \
  CXXFLAGS="-O3 -static" \
  LDFLAGS="-static -lz" || log_error "configure配置失败（检查依赖是否安装完整）"

# ===================== 步骤4：清理旧编译产物（configure之后执行，避免删配置） =====================
log_info "清理旧编译产物"
make clean || true  # 允许clean失败（首次编译无旧产物）

# ===================== 步骤5：多线程编译（用跨平台的CPU_CORES变量） =====================
log_info "开始多线程编译PopLDdecay（-j${CPU_CORES}）"
make -j${CPU_CORES} || log_error "PopLDdecay编译失败"

# ===================== 步骤6：复制静态编译产物到工程统一输出目录 =====================
log_info "复制编译产物到指定目录：${BUILD_OUTPUT_DIR}"
mkdir -p ${BUILD_OUTPUT_DIR}
cp -f PopLDdecay ${BUILD_OUTPUT_DIR}/${OUTPUT_NAME} || log_error "复制产物失败"

# ===================== 步骤7：验证纯静态编译产物 =====================
log_info "验证编译产物（静态链接+可执行性）"
if file ${BUILD_OUTPUT_DIR}/${OUTPUT_NAME} | grep -q -E "statically linked|Mach-O 64-bit executable"; then
  log_info "✅ PopLDdecay v3.43 跨平台编译成功！"
  log_info "产物路径：${BUILD_OUTPUT_DIR}/${OUTPUT_NAME}"
  ls -lh ${BUILD_OUTPUT_DIR}/${OUTPUT_NAME}
else
  log_error "❌ 编译产物非纯静态链接，请检查编译参数！"
fi
