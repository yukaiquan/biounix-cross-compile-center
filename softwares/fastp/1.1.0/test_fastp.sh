#!/bin/bash
# fastp Windows 测试脚本
# 运行: bash test_fastp.sh

set -e

FINAL_BIN="${1:-./fastp.exe}"

echo "=== fastp Windows 诊断测试 ==="
echo ""

echo "1. 检查文件存在:"
if [ -f "$FINAL_BIN" ]; then
    echo "   ✅ $FINAL_BIN 存在"
else
    echo "   ❌ $FINAL_BIN 不存在"
    exit 1
fi

echo ""
echo "2. 文件类型:"
file "$FINAL_BIN"

echo ""
echo "3. DLL 依赖:"
if command -v objdump &>/dev/null; then
    objdump -p "$FINAL_BIN" 2>/dev/null | grep -E "DLL Name" || echo "   无 DLL 依赖信息"
elif command -v strings &>/dev/null; then
    strings "$FINAL_BIN" | grep -E "\.dll$" | sort -u | head -20 || true
fi

echo ""
echo "4. 复制 DLL 后测试:"
# 创建临时测试目录
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# 复制所有 DLL
cp "${FINAL_BIN}" .
if [ -d "$(dirname "$FINAL_BIN")" ]; then
    cp "$(dirname "$FINAL_BIN")"/*.dll . 2>/dev/null || true
fi

echo "   测试目录: $TEST_DIR"
ls -la

echo ""
echo "5. 尝试运行（带调试输出）:"
# 尝试运行并捕获输出
timeout 10 "$FINAL_BIN" --version 2>&1 || {
    echo "   ❌ 运行失败，退出码: $?"
    echo ""
    echo "6. 尝试带-strace 运行:"
    timeout 10 "$FINAL_BIN" -i /dev/null -o /dev/null --disable-trim-quantitated-output 2>&1 || true
}

# 清理
rm -rf "$TEST_DIR"

echo ""
echo "=== 测试完成 ==="
