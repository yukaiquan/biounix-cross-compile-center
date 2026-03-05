#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env

# 2. 进入源码目录
cd "${SRC_PATH}"
log_info "Building megahit in: $(pwd)"

# 3. 初始化 submodules
if [ "$NEEDS_SUBMODULES" = "true" ]; then
    log_info "Initializing submodules..."
    git submodule update --init --recursive
fi

# 4. 修复 CMakeLists.txt 版本要求
if grep -q "cmake_minimum_required.*\.\.\." "${SRC_PATH}/CMakeLists.txt" 2>/dev/null; then
    log_info "Patching CMakeLists.txt for older CMake..."
    if command -v gsed &> /dev/null; then
        gsed -i 's/cmake_minimum_required(VERSION 3\.5\.\.\.4\.1)/cmake_minimum_required(VERSION 2.8)/' "${SRC_PATH}/CMakeLists.txt"
    else
        sed -i '' 's/cmake_minimum_required(VERSION 3\.5\.\.\.4\.1)/cmake_minimum_required(VERSION 2.8)/' "${SRC_PATH}/CMakeLists.txt" 2>/dev/null || \
        sed -i 's/cmake_minimum_required(VERSION 3\.5\.\.\.4\.1)/cmake_minimum_required(VERSION 2.8)/' "${SRC_PATH}/CMakeLists.txt"
    fi
fi

# 5. Windows 兼容性补丁
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows compatibility patches..."
    
    # 5.1 创建 compat.h
    cat > "${SRC_PATH}/src/utils/compat.h" << 'COMPAT_EOF'
/*
 * MegaHit Windows Compatibility Header
 */
#ifndef MEGAHIT_COMPAT_H
#define MEGAHIT_COMPAT_H

#ifdef _WIN32

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <psapi.h>

typedef unsigned int u_int;
typedef unsigned long ulong;
typedef long off_t;

static inline long getpagesize(void) {
    SYSTEM_INFO sys_info;
    GetSystemInfo(&sys_info);
    return sys_info.dwPageSize;
}

struct rusage {
    long ru_maxrss, ru_ixrss, ru_idrss, ru_isrss;
    long ru_minflt, ru_majflt, ru_nswap;
    long ru_inblock, ru_oublock;
    long ru_msgsnd, ru_msgrcv, ru_nsignals;
    long ru_nvcsw, ru_nivcsw;
};

#define RUSAGE_SELF 0
static inline int getrusage(int who, struct rusage *r) { 
    if (r) memset(r, 0, sizeof(struct rusage)); return 0; 
}

struct sysinfo {
    long uptime; unsigned long loads[3];
    unsigned long totalram, freeram, sharedram, bufferram;
    unsigned long totalswap, freeswap;
    unsigned short procs, _pad0;
    unsigned long totalhigh, freehigh;
    unsigned int mem_unit;
    char _f[20];
};

static inline int sysinfo(struct sysinfo *s) {
    if (!s) return -1;
    memset(s, 0, sizeof(struct sysinfo));
    MEMORYSTATUSEX m; m.dwLength = sizeof(m);
    if (GlobalMemoryStatusEx(&m)) {
        s->totalram = m.ullTotalPhys / 1024;
        s->freeram = m.ullAvailPhys / 1024;
        s->mem_unit = 1024;
    }
    return 0;
}

static inline unsigned int sleep(unsigned int s) { Sleep(s * 1000); return 0; }
static inline int usleep(unsigned int s) { Sleep(s / 1000); return 0; }
static inline int strcasecmp(const char *a, const char *b) { return _stricmp(a, b); }
static inline int strncasecmp(const char *a, const char *b, size_t n) { return _strnicmp(a, b, n); }

#endif // _WIN32
#endif // MEGAHIT_COMPAT_H
COMPAT_EOF

    # 5.2 下载并修补 utils.h
    log_info "Downloading and patching utils.h..."
    curl -sL "https://raw.githubusercontent.com/voutcn/megahit/v1.2.9/src/utils/utils.h" -o "${SRC_PATH}/src/utils/utils.h"
    
    # 在 #include "compat.h" 之后添加条件编译
    if ! grep -q "#ifndef _WIN32" "${SRC_PATH}/src/utils/utils.h"; then
        sed -i 's/^#include <fcntl.h>/#include "compat.h"\n\n#ifndef _WIN32\n#include <fcntl.h>/' "${SRC_PATH}/src/utils/utils.h"
        sed -i 's/^#include <sys\/resource.h>/#include <sys\/resource.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
        sed -i 's/^#include <sys\/time.h>/#include <sys\/time.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
        sed -i 's/^#include <unistd.h>/#include <unistd.h>\n#endif/' "${SRC_PATH}/src/utils/utils.h"
    fi
fi

# 6. 创建构建目录
cd "${SRC_PATH}"
rm -rf build
mkdir -p build
cd build

# 7. 配置编译
if [ "$OS_TYPE" == "linux" ]; then
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" -DSTATIC_BUILD=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5
elif [ "$OS_TYPE" == "macos" ]; then
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
elif [ "$OS_TYPE" == "windows" ]; then
    cmake .. -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" -DCMAKE_POLICY_VERSION_MINIMUM=3.5
fi

# 8. 编译
log_info "Compiling megahit..."
make -j${MAKE_JOBS}

# 9. 安装
log_info "Installing..."
make install

# 10. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/megahit${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN"
else
    log_err "Build artifact not found: $FINAL_BIN"
    exit 1
fi
