#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码目录
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid"
fi
cd "${SRC_PATH}"

# 3. 精准定位 CMake 根目录
if [ ! -f "CMakeLists.txt" ]; then
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi
log_info "Final build root: $(pwd)"

# --- 4. 终极源码补丁 (针对 Windows 深度系统调用) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying the 'Killer Patch' for Windows compatibility..."

    # 修复 A: 注入全能 Shim 到 common.h (带重定义保护)
    # 增加对 posix_memalign, sysconf, sysinfo, realpath, __cpuid 的全面模拟
    if [ -f "src/common.h" ]; then
        cat > mingw_shim.h <<'EOF'
#ifndef _MINGW_RAXML_SHIM_H
#define _MINGW_RAXML_SHIM_H
#ifdef _WIN32
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdarg.h>
#include <malloc.h>
#include <cpuid.h>

#ifdef __cplusplus
extern "C" {
#endif

// 1. 类型定义
typedef uint32_t u_int32_t;

// 2. asprintf 模拟
#ifndef _ASPRINTF_DEFINED
#define _ASPRINTF_DEFINED
static inline int asprintf(char **strp, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    int len = vsnprintf(NULL, 0, fmt, ap); va_end(ap);
    if (len < 0) return -1;
    *strp = (char *)malloc(len + 1);
    if (!*strp) return -1;
    va_start(ap, fmt);
    len = vsnprintf(*strp, len + 1, fmt, ap); va_end(ap);
    return len;
}
#endif

// 3. 内存管理模拟
#define posix_memalign(p, a, s) (((*(p)) = _aligned_malloc((s), (a))), ((*(p)) ? 0 : 12))

// 4. 系统信息模拟
struct sysinfo { uint64_t totalram; };
static inline int sysinfo(struct sysinfo* i) {
    MEMORYSTATUSEX s; s.dwLength = sizeof(s);
    GlobalMemoryStatusEx(&s);
    i->totalram = s.ullTotalPhys;
    return 0;
}

// 5. CPU 核心与路径模拟
#define _SC_NPROCESSORS_ONLN 1
static inline long sysconf(int n) {
    SYSTEM_INFO s; GetSystemInfo(&s);
    return s.dwNumberOfProcessors;
}
#define realpath(a, b) _fullpath((b), (a), 260)

// 6. CPUID 适配
#define __cpuid(info, level) __get_cpuid(level, (unsigned int*)&info[0], (unsigned int*)&info[1], (unsigned int*)&info[2], (unsigned int*)&info[3])

// 7. 资源占用模拟
#define RUSAGE_SELF 0
struct rusage { struct {long tv_sec; long tv_usec;} ru_utime, ru_stime; long ru_maxrss; };
static inline int getrusage(int w, struct rusage *r) { memset(r, 0, sizeof(struct rusage)); return 0; }

#ifdef __cplusplus
}
#endif
#endif
#endif
EOF
        # 强制把 shim 插到 common.h 的第一行
        cat mingw_shim.h src/common.h > src/common.h.tmp && mv src/common.h.tmp src/common.h
    fi

    # 修复 B: 暴力清洗 sysutil.cpp 中的 POSIX 引用
    log_info "Cleaning sysutil.cpp from unistd/sys headers..."
    sed -i 's/#include <sys\/resource.h>/\/\/ disabled/g' src/util/sysutil.cpp
    sed -i 's/#include <sys\/sysinfo.h>/\/\/ disabled/g' src/util/sysutil.cpp
    sed -i 's/#include <unistd.h>/\/\/ disabled/g' src/util/sysutil.cpp
    sed -i 's/u_int32_t/uint32_t/g' src/util/sysutil.cpp

    # 修复 C: 修改 CMakeLists.txt 以允许不规范转换并注入 -include
    sed -i '2i set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fpermissive -Wno-error=int-conversion")' CMakeLists.txt
    
    # 修复 D: 递归处理子模块
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) -exec sed -i 's/\berrno\b/pll_errno/g' {} +
    find libs -name "parse_utree.y" -exec sed -i 's/extern int pll_utree_parse();/struct pll_unode_s; int pll_utree_parse(struct pll_unode_s * tree);/g' {} +
    find libs -name "parse_rtree.y" -exec sed -i 's/extern int pll_rtree_parse();/struct pll_rnode_s; int pll_rtree_parse(struct pll_rnode_s * tree);/g' {} +
fi

# 5. 初始化 CMake 参数
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

case "${OS_TYPE}" in
    "windows")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles" ;;
    "macos")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}" ;;
    "linux")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles" ;;
esac

# 6. 执行构建
rm -rf build_dir && mkdir build_dir && cd build_dir
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}
make -j${MAKE_JOBS} || make

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
find . -name "raxml-ng${EXE_EXT}" -type f -exec cp -f {} "${INSTALL_PREFIX}/bin/" \;

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "CONGRATULATIONS! RAxML-NG build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found! Build failed at the final step."
    exit 1
fi
