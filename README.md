# cross-compile-center
通用跨平台编译工程中台 - 自动化编译各类软件的Linux/Windows/macOS静态二进制文件，基于GitHub Actions实现全自动化。

## 核心特性
1. 跨平台：支持Linux x64、Windows x64、macOS x64/arm64
2. 全静态：编译产物为纯静态二进制，无系统依赖，可直接分发
3. 自动化：GitHub Actions一键触发，自动拉取源码、安装依赖、编译、验证、上传产物
4. 易扩展：新增软件/版本仅需3步，无需修改核心代码
5. 高复用：通用逻辑封装为脚本/复用工作流，一次编写处处复用

## 目录结构

cross-compile-center/
├─ .github/ # GitHub Actions 工作流（复用 + 触发）
├─ softwares/ # 待编译软件配置（按软件 / 版本划分，核心可扩展目录）
├─ scripts/ # 全局通用执行脚本（所有软件共用，无硬编码）
├─ config/ # 全局配置文件（统一管理编译 / 平台 / 产物参数）
├─ logs/ # 本地编译日志（CI 不使用，.gitignore 忽略）
├─ build/ # 本地产物目录（CI 不使用，.gitignore 忽略）
└─ README.md # 项目说明文档

### 产物获取
1. **短期存储**：GitHub Actions Artifacts（默认保留30天，可在`config/artifact.env`修改）
2. **长期存储**：可扩展至GitHub Release（修改`scripts/upload_artifact.sh`即可实现）

## 技术栈
- 编译脚本：Bash（Windows通过MSYS2兼容，统一脚本语法）
- 自动化：GitHub Actions（Reusable Workflows 复用核心逻辑）
- 编译器：GCC/g++（Linux:apt | Windows:MinGW64 | macOS:brew）
- 依赖管理：apt（Linux）、pacman（Windows MSYS2）、brew（macOS）

## 常见问题
### Q1：编译失败提示“缺少依赖”？
A：检查`softwares/[软件]/[版本]/config.env`中的`DEPS_*`配置，确保对应平台依赖包名正确（Linux:apt包名 | Windows:MSYS2包名 | macOS:brew包名）。

### Q2：Windows编译无产物？
A：确保`build.sh`中的编译命令指定`.exe`后缀，且Windows编译步骤的`shell`为`msys2 {0}`（已在复用工作流中配置）。

### Q3：Linux产物不是纯静态？
A：1. 编译命令加`-static`参数（在`config.env`的`LDFLAGS`中配置）；2. 确保安装了静态开发库（如zlib1g-dev，而非zlib1g）。
