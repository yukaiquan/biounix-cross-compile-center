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

# 3. 定位 CMake 根目录
if [ ! -f "CMakeLists.txt" ]; then
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi
log_info "Final build root: $(pwd)"

# --- 4. 源码深度补丁 (针对 Windows/MinGW 最终修复) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying deep compatibility patches for Windows..."

    # 修复 A: 注入全能 Shim 到 src/common.h
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

#ifdef __cplusplus
extern "C" {
#endif

/* 基础类型补全 */
typedef uint32_t u_int32_t;

/* asprintf 模拟 */
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

/* 内存管理：直接映射为 malloc 以配合 free() */
#define posix_memalign(p, a, s) (((*(p)) = malloc((s))), ((*(p)) ? 0 : 12))

/* 系统信息模拟 (补全所有成员) */
struct sysinfo { uint64_t totalram; int mem_unit; };
static inline int sysinfo(struct sysinfo* i) {
    MEMORYSTATUSEX s; s.dwLength = sizeof(s);
    GlobalMemoryStatusEx(&s);
    i->totalram = s.ullTotalPhys;
    i->mem_unit = 1;
    return 0;
}

/* CPU 与路径模拟 */
#define _SC_NPROCESSORS_ONLN 1
static inline long sysconf(int n) {
    SYSTEM_INFO s; GetSystemInfo(&s);
    return s.dwNumberOfProcessors;
}
#define realpath(a, b) _fullpath((b), (a), 260)

/* 资源占用模拟 */
#define RUSAGE_SELF 0
struct rusage { struct {long tv_sec; long tv_usec;} ru_utime, ru_stime; long ru_maxrss; };
static inline int getrusage(int w, struct rusage *r) { 
    memset(r, 0, sizeof(struct rusage)); return 0; 
}

#ifdef __cplusplus
}
#endif
#endif
#endif
EOF
    cat mingw_shim.h src/common.h > src/common.h.tmp && mv src/common.h.tmp src/common.h

    # 修复 B: 针对 sysutil.cpp 的“外科手术”
    log_info "Surgically fixing sysutil.cpp..."
    # 屏蔽不兼容头文件
    sed -i 's/#include <sys\/resource.h>/\/\/ shim/g' src/util/sysutil.cpp
    sed -i 's/#include <sys\/sysinfo.h>/\/\/ shim/g' src/util/sysutil.cpp
    sed -i 's/#include <unistd.h>/\/\/ shim/g' src/util/sysutil.cpp
    
    # 核心：直接把源码里的 __cpuid(out, x) 替换为 MinGW 的 __get_cpuid
    # 同时在文件头部引入 cpuid.h
    sed -i '1i #include <cpuid.h>' src/util/sysutil.cpp
    sed -i 's/__cpuid(out, x);/__get_cpuid(x, (unsigned int*)\&out[0], (unsigned int*)\&out[1], (unsigned int*)\&out[2], (unsigned int*)\&out[3]);/g' src/util/sysutil.cpp
    sed -i 's/__cpuid(info, 0);/__get_cpuid(0, (unsigned int*)\&info[0], (unsigned int*)\&info[1], (unsigned int*)\&info[2], (unsigned int*)\&info[3]);/g' src/util/sysutil.cpp
    sed -i 's/__cpuid(info, nExIds);/__get_cpuid(nExIds, (unsigned int*)\&info[0], (unsigned int*)\&info[1], (unsigned int*)\&info[2], (unsigned int*)\&info[3]);/g' src/util/sysutil.cpp

    # 修复 C: 修改 CMakeLists.txt 禁用 SIMD 并屏蔽警告
    sed -i '2i set(ENABLE_RAXML_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    sed -i '3i set(ENABLE_PLLMOD_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    sed -i '4i set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fpermissive -Wno-error=int-conversion -Wno-error=unused-parameter -Wno-maybe-uninitialized")' CMakeLists.txt
    
    # 修复 D: 子模块补丁 (errno 和 Bison)
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) -exec sed -i 's/\berrno\b/pll_errno/g' {} +
    find libs -name "parse_utree.y" -exec sed -i 's/extern int pll_utree_parse();/struct pll_unode_s; int pll_utree_parse(struct pll_unode_s * tree);/g' {} +
    find libs -name "parse_rtree.y" -exec sed -i 's/extern int pll_rtree_parse();/struct pll_rnode_s; int pll_rtree_parse(struct pll_rnode_s * tree);/g' {} +
fi

# 5. CMake 参数
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DSTATIC_BUILD=ON"

case "${OS_TYPE}" in
    "windows")
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles" ;;
    "macos")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}" ;;
    "linux")
        GENERATOR="Unix Makefiles" ;;
esac

# 6. 执行构建
rm -rf build_dir && mkdir build_dir && cd build_dir
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}
make -j${MAKE_JOBS} || make

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
FOUND_BIN=$(find . -name "raxml-ng*${EXE_EXT}" -type f | grep -v "test" | head -n 1)
if [ -n "$FOUND_BIN" ]; then
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
    log_info "Binary collected: raxml-ng${EXE_EXT}"
else
    log_err "Binary not found!"
    exit 1
fi

log_info "Build successful!"
