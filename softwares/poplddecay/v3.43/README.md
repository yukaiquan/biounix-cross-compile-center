# PopLDdecay v3.43 编译说明
## 编译要求
- 编译语言：C++11及以上
- 核心依赖：zlib（静态开发库）
- 编译器：GCC/g++ 5.0及以上

## 编译命令
核心命令：`g++ src/LD_Decay.cpp -o PopLDdecay -O2 -std=c++11 -static -lz`
- `-static`：纯静态编译，无系统依赖
- `-lz`：链接zlib压缩库（项目唯一外部依赖）

## 产物说明
- 原始产物名：PopLDdecay（Windows为PopLDdecay.exe）
- 功能：群体遗传学LD衰减分析工具
- 运行方式：`./PopLDdecay -in [vcf文件] -out [输出前缀]`

## 已知问题
1. macOS下纯静态编译可能警告，不影响功能使用；
2. Windows下需用MinGW64编译器，MSVC编译需修改源码（未测试）。
