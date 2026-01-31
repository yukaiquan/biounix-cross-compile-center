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

# --- 4. 源码深度补丁 (针对 ML Search 崩溃的专项修复) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying CRITICAL stability patches for ML search..."

    # 修复 A: 注入带 va_copy 的安全 Shim (解决内存非法访问根源)
    cat > mingw_shim.h <<'EOF'
#ifndef _RAXML_STABILITY_SHIM_H
#define _RAXML_STABILITY_SHIM_H
#ifdef _WIN32
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdarg.h>
#include <malloc.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t u_int32_t;

/* 核心修复：使用 va_copy 确保 asprintf 在 Windows 下绝对安全 */
#ifndef _ASPRINTF_DEFINED
#define _ASPRINTF_DEFINED
static inline int asprintf(char **strp, const char *fmt, ...) {
    va_list ap, ap2;
    va_start(ap, fmt);
    va_copy(ap2, ap);
    int len = _vscprintf(fmt, ap);
    va_end(ap);
    if (len < 0) { va_end(ap2); return -1; }
    *strp = (char *)malloc(len + 1);
    if (!*strp) { va_end(ap2); return -1; }
    len = vsnprintf(*strp, len + 1, fmt, ap2);
    va_end(ap2);
    return len;
}
#endif

/* 内存对齐映射：配合禁用自动向量化，防止对齐引起的段错误 */
#ifndef posix_memalign
#define posix_memalign(p, a, s) (((*(p)) = malloc((s))), ((*(p)) ? 0 : 12))
#endif

struct sysinfo { uint64_t totalram; int mem_unit; };
static inline int sysinfo(struct sysinfo* i) {
    MEMORYSTATUSEX s; s.dwLength = sizeof(s);
    GlobalMemoryStatusEx(&s);
    i->totalram = s.ullTotalPhys;
    i->mem_unit = 1;
    return 0;
}

#define _SC_NPROCESSORS_ONLN 1
static inline long sysconf(int n) {
    (void)n;
    SYSTEM_INFO s; GetSystemInfo(&s);
    return s.dwNumberOfProcessors;
}
#define realpath(a, b) _fullpath((b), (a), 260)

#define RUSAGE_SELF 0
struct rusage { struct {long tv_sec; long tv_usec;} ru_utime, ru_stime; long ru_maxrss; };
static inline int getrusage(int w, struct rusage *r) { 
    (void)w; memset(r, 0, sizeof(struct rusage)); return 0; 
}

#ifdef __cplusplus
}
#endif
#endif
#endif
EOF
    cat mingw_shim.h src/common.h > src/common.h.tmp && mv src/common.h.tmp src/common.h

    # 修复 B: 强力拦截编译器优化 (防止生成非对齐的 SSE 指令)
    log_info "Overriding CMakeLists.txt to force safety..."
    # 强制禁用所有 SIMD 加速，这是 Windows 版不崩溃的底线
    sed -i '2i set(ENABLE_RAXML_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    sed -i '3i set(ENABLE_PLLMOD_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    # 注入参数：-mno-sse 彻底关闭向量化；-fpermissive 允许代码不规范；16MB 栈空间防止树搜索爆栈
    sed -i '4i set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fpermissive -mno-sse -mno-sse2 -mno-avx -Wl,--stack,16777216")' CMakeLists.txt
    sed -i '5i set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mno-sse -mno-sse2 -mno-avx")' CMakeLists.txt

    # 修复 C: 屏蔽系统头文件
    sed -i '1i #include <cpuid.h>' src/util/sysutil.cpp
    sed -i 's/#include <sys\/resource.h>/\/\/ shim/g' src/util/sysutil.cpp
    sed -i 's/#include <sys\/sysinfo.h>/\/\/ shim/g' src/util/sysutil.cpp
    sed -i 's/#include <unistd.h>/\/\/ shim/g' src/util/sysutil.cpp
    
    # 修复 D: 递归修正变量冲突
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) -exec sed -i 's/\berrno\b/pll_errno/g' {} +
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +
    
    # 修复 E: 移除 Bison 陈旧声明 (防止冲突)
    find libs -name "parse_utree.y" -exec sed -i '/extern int pll_utree_parse();/d' {} +
    find libs -name "parse_rtree.y" -exec sed -i '/extern int pll_rtree_parse();/d' {} +
fi

# 5. CMake 统一执行
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DSTATIC_BUILD=ON"

case "${OS_TYPE}" in
    "windows")
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles" ;;
    *)
        GENERATOR="Unix Makefiles" ;;
esac

# 6. 执行编译
rm -rf build_dir && mkdir build_dir && cd build_dir
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}
make -j${MAKE_JOBS} || make

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find . -name "raxml-ng*${EXE_EXT}" -type f | grep -v "test" | head -n 1)
cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"

log_info "Build success! This version is optimized for Windows stability."
