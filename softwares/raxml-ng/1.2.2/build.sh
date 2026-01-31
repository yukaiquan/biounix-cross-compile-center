#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid"
fi
cd "${SRC_PATH}"

# 3. 定位真实根目录
if [ ! -f "CMakeLists.txt" ]; then
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi

# --- 4. 源码手术 (针对 Windows GCC15 稳定版) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Executing surgical fix for Windows GCC15..."

    # 修复 A: 暴力替换 sysutil.cpp 中的 __cpuid 调用，彻底避开宏冲突
    # 我们先将其改名，然后在 shim 中定义它
    sed -i 's/\b__cpuid(/RAXML_MINGW_CPUID(/g' src/util/sysutil.cpp
    sed -i 's/u_int32_t/uint32_t/g' src/util/sysutil.cpp
    # 注释掉所有 POSIX 头文件
    sed -i 's/#include <sys\/resource.h>/\/\/ disabled/g' src/util/sysutil.cpp
    sed -i 's/#include <sys\/sysinfo.h>/\/\/ disabled/g' src/util/sysutil.cpp
    sed -i 's/#include <unistd.h>/\/\/ disabled/g' src/util/sysutil.cpp

    # 修复 B: 创建一个干净的 shim.h
    cat > mingw_fix.h <<'EOF'
#ifndef _RAXML_MINGW_FIX_H
#define _RAXML_MINGW_FIX_H
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdarg.h>
#include <malloc.h>
#include <string.h>
#include <cpuid.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 1. 安全的 asprintf 实现 (解决 ML Search 崩溃的关键) */
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

/* 2. 内存对齐：在禁用 SIMD 情况下，malloc 是最安全的 */
#define posix_memalign(p, a, s) (((*(p)) = malloc((s))), ((*(p)) ? 0 : 12))

/* 3. 系统信息模拟 (补全所有成员，解决 sysutil.cpp 170行报错) */
struct sysinfo { uint64_t totalram; int mem_unit; };
static inline int sysinfo(struct sysinfo* i) {
    MEMORYSTATUSEX s; s.dwLength = sizeof(s);
    GlobalMemoryStatusEx(&s);
    i->totalram = s.ullTotalPhys;
    i->mem_unit = 1;
    return 0;
}

/* 4. CPU 与 路径模拟 */
#define _SC_NPROCESSORS_ONLN 1
static inline long sysconf(int n) {
    SYSTEM_INFO s; GetSystemInfo(&s);
    return s.dwNumberOfProcessors;
}
#define realpath(a, b) _fullpath((b), (a), 260)

/* 5. 资源占用模拟 */
#define RUSAGE_SELF 0
struct rusage { struct {long tv_sec; long tv_usec;} ru_utime, ru_stime; long ru_maxrss; };
static inline int getrusage(int w, struct rusage *r) { 
    memset(r, 0, sizeof(struct rusage)); return 0; 
}

/* 6. CPUID 适配：映射我们改名后的调用 */
#define RAXML_MINGW_CPUID(out, level) __get_cpuid(level, (unsigned int*)&out[0], (unsigned int*)&out[1], (unsigned int*)&out[2], (unsigned int*)&out[3])

#ifdef __cplusplus
}
#endif
#endif
EOF

    # 修复 C: 强制让编译器包含我们的补丁 (最稳的方法，不需要改源码 include)
    # 修改 CMake 注入全局参数
    sed -i "2i set(CMAKE_CXX_FLAGS \"\${CMAKE_CXX_FLAGS} -include \\\"\${CMAKE_CURRENT_SOURCE_DIR}/mingw_fix.h\\\" -fpermissive -mno-sse -mno-avx -Wl,--stack,16777216\")" CMakeLists.txt
    sed -i "3i set(CMAKE_C_FLAGS \"\${CMAKE_C_FLAGS} -include \\\"\${CMAKE_CURRENT_SOURCE_DIR}/mingw_fix.h\\\" -Wno-int-conversion\")" CMakeLists.txt
    
    # 强制禁用 SIMD 以保证稳定性
    sed -i '4i set(ENABLE_RAXML_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    sed -i '5i set(ENABLE_PLLMOD_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt

    # 修复 D: 递归修正子项目
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) -exec sed -i 's/\berrno\b/pll_errno/g' {} +
    find libs -name "parse_utree.y" -exec sed -i '/extern int pll_utree_parse();/d' {} +
    find libs -name "parse_rtree.y" -exec sed -i '/extern int pll_rtree_parse();/d' {} +
fi

# 5. CMake 参数
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DSTATIC_BUILD=ON"

case "${OS_TYPE}" in
    "windows")
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles" ;;
    *)
        GENERATOR="Unix Makefiles" ;;
esac

# 6. 构建
rm -rf build_dir && mkdir build_dir && cd build_dir
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}
make -j${MAKE_JOBS} || make

# 7. 整理
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find . -name "raxml-ng*${EXE_EXT}" -type f | grep -v "test" | head -n 1)
cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"

log_info "DONE! Windows binary created with stability shim."
