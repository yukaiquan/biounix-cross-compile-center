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

# 4. 修复 CMakeLists.txt 版本要求（如果有 range 语法）
if grep -q "cmake_minimum_required.*\.\.\." "${SRC_PATH}/CMakeLists.txt" 2>/dev/null; then
    log_info "Patching CMakeLists.txt for older CMake..."
    # macOS 使用 gsed，Linux 用 sed
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
    
    # 创建 compat.h 头文件
    COMPAT_H="${SRC_PATH}/src/utils/compat.h"
    log_info "Creating ${COMPAT_H}..."
    
    cat > "${COMPAT_H}" << 'COMPAT_EOF'
/*
 * MegaHit Windows Compatibility Header
 * Provides Windows equivalents for POSIX functions
 */

#ifndef MEGAHIT_COMPAT_H
#define MEGAHIT_COMPAT_H

#ifdef _WIN32

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <psapi.h>

// Define POSIX types
typedef int pid_t;
typedef unsigned int u_int;
typedef unsigned long ulong;
typedef long off_t;

// getpagesize - Windows equivalent
static inline long getpagesize(void) {
    SYSTEM_INFO sys_info;
    GetSystemInfo(&sys_info);
    return sys_info.dwPageSize;
}

// getrusage stub
struct rusage {
    long ru_maxrss;
    long ru_ixrss;
    long ru_idrss;
    long ru_isrss;
    long ru_minflt;
    long ru_majflt;
    long ru_nswap;
    long ru_inblock;
    long ru_oublock;
    long ru_msgsnd;
    long ru_msgrcv;
    long ru_nsignals;
    long ru_nvcsw;
    long ru_nivcsw;
};

#define RUSAGE_SELF 0

static inline int getrusage(int who, struct rusage *usage) {
    if (usage) {
        memset(usage, 0, sizeof(struct rusage));
    }
    return 0;
}

// sysinfo stub
struct sysinfo {
    long uptime;
    unsigned long loads[3];
    unsigned long totalram;
    unsigned long freeram;
    unsigned long sharedram;
    unsigned long bufferram;
    unsigned long totalswap;
    unsigned long freeswap;
    unsigned short procs;
    unsigned short _pad0;
    unsigned long totalhigh;
    unsigned long freehigh;
    unsigned int mem_unit;
    char _f[20];
};

static inline int sysinfo(struct sysinfo *info) {
    if (!info) return -1;
    memset(info, 0, sizeof(struct sysinfo));
    MEMORYSTATUSEX mem;
    mem.dwLength = sizeof(mem);
    if (GlobalMemoryStatusEx(&mem)) {
        info->totalram = mem.ullTotalPhys / 1024;
        info->freeram = mem.ullAvailPhys / 1024;
        info->mem_unit = 1024;
    }
    return 0;
}

// stat structures
struct stat {
    _dev_t st_dev;
    _ino_t st_ino;
    unsigned short st_mode;
    short st_nlink;
    short st_uid;
    short st_gid;
    int _pad0;
    _dev_t st_rdev;
    _off_t st_size;
    long st_atime;
    long st_mtime;
    long st_ctime;
    long st_blksize;
    long st_blocks;
};

#define S_IFMT  0170000
#define S_IFDIR 0040000
#define S_IFREG 0100000

// fstat
static inline int fstat(int fd, struct stat *st) {
    return _fstat(fd, st);
}

// isatty
static inline int isatty(int fd) {
    return _isatty(fd);
}

// sleep (in seconds)
static inline unsigned int sleep(unsigned int seconds) {
    Sleep(seconds * 1000);
    return 0;
}

// usleep
static inline int usleep(unsigned int usec) {
    Sleep(usec / 1000);
    return 0;
}

// strcasecmp
static inline int strcasecmp(const char *s1, const char *s2) {
    return _stricmp(s1, s2);
}

// strncasecmp  
static inline int strncasecmp(const char *s1, const char *s2, size_t n) {
    return _strnicmp(s1, s2, n);
}

// open/close/read/write wrappers
#define O_RDONLY _O_RDONLY
#define O_WRONLY _O_WRONLY
#define O_CREAT _O_CREAT
#define O_RDWR _O_RDWR

static inline int open(const char *path, int flags, ...) {
    int mode = 0;
    va_list args;
    va_start(args, flags);
    mode = va_arg(args, int);
    va_end(args);
    return _open(path, flags, mode);
}

static inline int close(int fd) {
    return _close(fd);
}

static inline int read(int fd, void *buf, unsigned int count) {
    return _read(fd, buf, count);
}

static inline int write(int fd, const void *buf, unsigned int count) {
    return _write(fd, buf, count);
}

// lseek
static inline off_t lseek(int fd, off_t offset, int whence) {
    return _lseek(fd, offset, whence);
}

// getcwd
static inline char *getcwd(char *buf, size_t size) {
    return _getcwd(buf, size);
}

// unlink
static inline int unlink(const char *path) {
    return _unlink(path);
}

// rmdir
static inline int rmdir(const char *path) {
    return _rmdir(path);
}

// mkdir
static inline int mkdir(const char *path, int mode) {
    return _mkdir(path);
}

// getpid
static inline pid_t getpid(void) {
    return GetCurrentProcessId();
}

// getuid
static inline int getuid(void) {
    return 0;
}

// geteuid
static inline int geteuid(void) {
    return 0;
}

#endif // _WIN32

#endif // MEGAHIT_COMPAT_H
COMPAT_EOF

    # 补丁 utils.h - 直接写入修补后的版本
    log_info "Patching src/utils/utils.h..."
    UTILS_H="${SRC_PATH}/src/utils/utils.h"
    
    cat > "${UTILS_H}" << 'UTILS_EOF'
/*
 *  MEGAHIT
 *  Copyright (C) 2014 - 2015 The University of Hong Kong & L3 Bioinformatics
 * Limited
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/* contact: Dinghua Li <dhli@cs.hku.hk> */

#ifndef MEGAHIT_UTILS_H
#define MEGAHIT_UTILS_H

// Include Windows compatibility header first
#include "compat.h"

#ifndef _WIN32
#include <fcntl.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <unistd.h>
#endif

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <istream>

#include "pprintpp/pprintpp.hpp"

UTILS_EOF
    
    # 补丁 parallel_hashmap/meminfo.h - 添加 getpagesize
    MEMINFO_H="${SRC_PATH}/src/parallel_hashmap/meminfo.h"
    log_info "Patching src/parallel_hashmap/meminfo.h..."
    
    # 检查是否已有 getpagesize 定义
    if ! grep -q "getpagesize.*Windows" "${MEMINFO_H}" 2>/dev/null; then
        # 在 SPP_WIN 部分添加 getpagesize
        if command -v gsed &> /dev/null; then
            gsed -i '/#ifdef SPP_WIN/,/MEMORYSTATUSEX mem;/{
                /#include <Psapi.h>/a\
\
    // getpagesize for Windows\
    static inline long getpagesize(void) {\
        SYSTEM_INFO sys_info;\
        GetSystemInfo(\&sys_info);\
        return sys_info.dwPageSize;\
    }
            }' "${MEMINFO_H}"
        else
            sed -i '' '/#ifdef SPP_WIN/,/MEMORYSTATUSEX mem;/{
                /#include <Psapi.h>/a\
\
    // getpagesize for Windows\
    static inline long getpagesize(void) {\
        SYSTEM_INFO sys_info;\
        GetSystemInfo(\&sys_info);\
        return sys_info.dwPageSize;\
    }
            }' "${MEMINFO_H}" 2>/dev/null || true
        fi
    fi
fi

# 6. 创建构建目录
cd "${SRC_PATH}"
rm -rf build
mkdir -p build
cd build

# 7. 配置编译选项
if [ "$OS_TYPE" == "linux" ]; then
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-O3 -DNDEBUG"
    export CXXFLAGS="-O3 -DNDEBUG -fopenmp"
    export LDFLAGS="-fopenmp -static"
    
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DSTATIC_BUILD=ON \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5

elif [ "$OS_TYPE" == "macos" ]; then
    export CC="clang"
    export CXX="clang++"
    export CFLAGS="-O3 -DNDEBUG"
    export CXXFLAGS="-O3 -DNDEBUG -std=c++11 -fopenmp"
    
    # macOS 不支持静态链接 OpenMP，使用动态链接
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"

elif [ "$OS_TYPE" == "windows" ]; then
    # Windows MSYS2 环境
    # 使用系统默认的编译器 (gcc from mingw)
    cmake .. \
        -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
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
    ls -la "$FINAL_BIN"
    
    # 显示版本
    "$FINAL_BIN" --version 2>&1 | head -3 || true
else
    log_err "Build artifact not found: $FINAL_BIN"
    # 尝试其他可能的路径
    ls -la "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
    exit 1
fi
