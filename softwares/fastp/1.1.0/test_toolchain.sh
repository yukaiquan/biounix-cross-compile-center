#!/bin/bash
# 快速测试 Windows 工具链

set -e

echo "=== 测试 Windows 工具链 ==="

# 1. 测试 gcc 是否正常
echo ""
echo "1. 测试 GCC:"
cat > /tmp/test.c << 'EOF'
#include <stdio.h>
int main() { printf("Hello from C\n"); return 0; }
EOF

if command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    x86_64-w64-mingw32-gcc /tmp/test.c -o /tmp/test.exe
    echo "   ✅ GCC 编译成功"
    file /tmp/test.exe
else
    echo "   ❌ GCC 未找到"
fi

# 2. 测试 clang 是否正常
echo ""
echo "2. 测试 Clang:"
cat > /tmp/test2.c << 'EOF'
#include <stdio.h>
int main() { printf("Hello from Clang\n"); return 0; }
EOF

if command -v clang &>/dev/null; then
    clang /tmp/test2.c -o /tmp/test2.exe
    echo "   ✅ Clang 编译成功"
    file /tmp/test2.exe
else
    echo "   ❌ Clang 未找到"
fi

# 3. 测试 C++ 编译器
echo ""
echo "3. 测试 C++:"
cat > /tmp/test.cpp << 'EOF'
#include <iostream>
int main() { std::cout << "Hello from C++" << std::endl; return 0; }
EOF

if command -v x86_64-w64-mingw32-g++ &>/dev/null; then
    x86_64-w64-mingw32-g++ /tmp/test.cpp -o /tmp/test_cpp.exe
    echo "   ✅ G++ 编译成功"
    file /tmp/test_cpp.exe
elif command -v clang++ &>/dev/null; then
    clang++ /tmp/test.cpp -o /tmp/test_cpp.exe
    echo "   ✅ Clang++ 编译成功"
    file /tmp/test_cpp.exe
else
    echo "   ❌ C++ 编译器未找到"
fi

# 4. 测试 libdeflate
echo ""
echo "4. 测试 libdeflate:"
cat > /tmp/test_deflate.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include "libdeflate.h"
int main() {
    struct libdeflate_decompressor *d = libdeflate_alloc_decompressor();
    if (d) { printf("libdeflate OK\n"); libdeflate_free_decompressor(d); return 0; }
    return 1;
}
EOF

if command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    x86_64-w64-mingw32-gcc /tmp/test_deflate.c -o /tmp/test_deflate.exe -ldeflate 2>&1 || echo "   ⚠️ libdeflate 链接失败（可能需要 DLL）"
    if [ -f /tmp/test_deflate.exe ]; then
        file /tmp/test_deflate.exe
    fi
fi

echo ""
echo "=== 测试完成 ==="
