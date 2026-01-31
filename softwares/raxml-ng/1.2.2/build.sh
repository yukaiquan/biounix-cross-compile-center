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

# --- 4. 源码深度补丁 (针对 Windows/GCC 15 的全量修复) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying deep-level Windows stability and compatibility patches..."

    # 修复 A: 注入全向 Shim (解决 asprintf, sysinfo, 栈空间, 内存对齐)
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

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t u_int32_t;

/* 使用 Windows 特有 API 实现安全的 asprintf，防止内存计算错误导致崩溃 */
#ifndef _ASPRINTF_DEFINED
#define _ASPRINTF_DEFINED
static inline int asprintf(char **strp, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int len = _vscprintf(fmt, ap);
    va_end(ap);
    if (len < 0) return -1;
    *strp = (char *)malloc(len + 1);
    if (!*strp) return -1;
    va_start(ap, fmt);
    len = vsnprintf(*strp, len + 1, fmt, ap);
    va_end(ap);
    return len;
}
#endif

/* 内存对齐映射：配合禁用 SIMD，使用 malloc 是最稳妥的，防止 free() 崩溃 */
#ifndef posix_memalign
#define posix_memalign(p, a, s) (((*(p)) = malloc((s))), ((*(p)) ? 0 : 12))
#endif

/* 系统资源模拟 */
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
    # 强制将补丁注入核心头文件
    cat mingw_shim.h src/common.h > src/common.h.tmp && mv src/common.h.tmp src/common.h

    # 修复 B: 解决 bison/yacc 函数原型冲突 (解决 conflicting types 报错)
    # 策略：直接删除源码中陈旧的 extern 声明，让编译器使用生成的正确声明
    log_info "Removing obsolete parser declarations..."
    find libs -name "parse_utree.y" -exec sed -i '/extern int pll_utree_parse();/d' {} +
    find libs -name "parse_rtree.y" -exec sed -i '/extern int pll_rtree_parse();/d' {} +
    # 修正 Bison 语法
    find libs -name "*.y" -exec sed -i 's/%error-verbose/%define parse.error verbose/g' {} +

    # 修复 C: 针对 sysutil.cpp 的外科手术 (解决 __cpuid 报错)
    log_info "Fixing sysutil.cpp hardware detection..."
    sed -i '1i #include <cpuid.h>' src/util/sysutil.cpp
    sed -i 's/#include <sys\/resource.h>/\/\/ shim/g' src/util/sysutil.cpp
    sed -i 's/#include <sys\/sysinfo.h>/\/\/ shim/g' src/util/sysutil.cpp
    sed -i 's/#include <unistd.h>/\/\/ shim/g' src/util/sysutil.cpp
    sed -i 's/__cpuid(out, x);/__get_cpuid(x, (unsigned int*)\&out[0], (unsigned int*)\&out[1], (unsigned int*)\&out[2], (unsigned int*)\&out[3]);/g' src/util/sysutil.cpp
    sed -i 's/__cpuid(info, 0);/__get_cpuid(0, (unsigned int*)\&info[0], (unsigned int*)\&info[1], (unsigned int*)\&info[2], (unsigned int*)\&info[3]);/g' src/util/sysutil.cpp
    sed -i 's/__cpuid(info, nExIds);/__get_cpuid(nExIds, (unsigned int*)\&info[0], (unsigned int*)\&info[1], (unsigned int*)\&info[2], (unsigned int*)\&info[3]);/g' src/util/sysutil.cpp

    # 修复 D: 修改 CMakeLists.txt 强制稳定性设置
    # 1. 禁用 SIMD 防止对齐指令崩溃 2. 注入宽容编译参数 3. 提升栈空间到 16MB 防止爆栈
    sed -i '2i set(ENABLE_RAXML_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    sed -i '3i set(ENABLE_PLLMOD_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    sed -i '4i set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fpermissive -mno-sse -mno-avx -Wno-error=int-conversion -Wno-error=use-after-free")' CMakeLists.txt
    sed -i '5i set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--stack,16777216")' CMakeLists.txt

    # 修复 E: 替换子模块中的 errno (防止宏冲突)
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) -exec sed -i 's/\berrno\b/pll_errno/g' {} +
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +
fi

# 5. CMake 编译参数
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
    *)
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
    log_info "Binary saved as: raxml-ng${EXE_EXT}"
else
    log_err "Binary not found!"
    exit 1
fi

log_info "Build finished. Windows stability shim applied."
