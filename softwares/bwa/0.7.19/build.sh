#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa in: $(pwd)"

# 3. Windows 特殊处理
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Building for Windows (MSYS2)..."
    
    # 直接修改源文件 - 定义宏替代缺失的头文件
    for file in utils.c; do
        [ -f "$file" ] || continue
        
        # 在文件开头添加 Windows 兼容定义
        cat > ${file}.winpatch << 'PATCHEOF'
#ifdef _WIN32
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <io.h>

typedef struct {
    long tv_sec;
    long tv_usec;
    long tv_maxrss;
} rusage_t;

#define RUSAGE_SELF 0

static inline int getrusage(int who, rusage_t *r) {
    (void)who;
    if (r) memset(r, 0, sizeof(rusage_t));
    return 0;
}

static inline long lrand48(void) {
    return (long)((rand() << 16) ^ rand());
}

static inline void srand48(long seed) {
    srand((unsigned int)seed);
}

#define fsync _commit
#define HAVE_PTHREAD
#endif

PATCHEOF
        
        # 在第一个 #include 之前插入
        sed -i '/^#include/r '"${file}.winpatch" "$file"
        rm -f "${file}.winpatch"
        
        log_info "Patched: $file"
    done
    
    # bntseq.c 同样处理
    for file in bntseq.c; do
        [ -f "$file" ] || continue
        
        cat > ${file}.winpatch << 'PATCHEOF'
#ifdef _WIN32
#include <stdlib.h>
static inline long lrand48(void) { return (long)((rand() << 16) ^ rand()); }
static inline void srand48(long seed) { srand((unsigned int)seed); }
#endif

PATCHEOF
        sed -i '/^#include/r '"${file}.winpatch" "$file"
        rm -f "${file}.winpatch"
        
        log_info "Patched: $file"
    done
    
    # 清理
    make clean 2>/dev/null || true
    
    # 编译
    log_info "Compiling..."
    make -j${MAKE_JOBS} \
        CC=gcc \
        CFLAGS="-g -Wall -O3 -static -DHAVE_PTHREAD -DUSE_MALLOC_WRAPPERS" \
        LDFLAGS="-static -static-libgcc -static-libstdc++" \
        LIBS="-lm -lz -lpthread"
        
else
    # 非 Windows
    export CFLAGS="-g -Wall -Wno-unused-function -O3"
    export LIBS="-lm -lz -lpthread"
    
    case "${OS_TYPE}" in
        "macos")
            log_info "Building for macOS..."
            [ -d "/opt/homebrew/opt/zlib" ] && export CFLAGS="${CFLAGS} -I/opt/homebrew/opt/zlib/include"
            ;;
        
        "linux")
            log_info "Building for Linux..."
            export LIBS="${LIBS} -lrt"
            export LDFLAGS="-static"
            ;;
    esac
    
    make clean 2>/dev/null || true
    make -j${MAKE_JOBS}
fi

# 4. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bwa${EXE_EXT} "${INSTALL_PREFIX}/bin/"

# 5. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa installed to ${INSTALL_PREFIX}/bin/"
