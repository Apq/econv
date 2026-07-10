# Linux 和 macOS 构建与发布

本文档说明如何使用 vcpkg、CMake、Ninja 和 CTest 构建并发布 Linux x64、macOS arm64、macOS x64 版本。

## 前置条件

所有平台都需要：

- CMake 3.20+
- Ninja
- Git
- vcpkg
- C++17 编译器
- `tar`

Linux（Ubuntu/Debian）可安装：

```bash
sudo apt update
sudo apt install -y build-essential cmake ninja-build git curl zip unzip tar pkg-config
```

macOS 可安装：

```bash
xcode-select --install
brew install cmake ninja git
```

安装并初始化 vcpkg：

```bash
git clone https://github.com/microsoft/vcpkg.git "$HOME/vcpkg"
"$HOME/vcpkg/bootstrap-vcpkg.sh"
export VCPKG_ROOT="$HOME/vcpkg"
```

## CMake Presets

项目提供以下 configure/build/test presets：

```text
linux-x64-vcpkg / linux-x64-release / linux-x64-tests
macos-arm64-vcpkg / macos-arm64-release / macos-arm64-tests
macos-x64-vcpkg / macos-x64-release / macos-x64-tests
```

Linux x64：

```bash
cmake --preset linux-x64-vcpkg
cmake --build --preset linux-x64-release
ctest --preset linux-x64-tests
```

macOS Apple Silicon：

```bash
cmake --preset macos-arm64-vcpkg
cmake --build --preset macos-arm64-release
ctest --preset macos-arm64-tests
```

macOS Intel：

```bash
cmake --preset macos-x64-vcpkg
cmake --build --preset macos-x64-release
ctest --preset macos-x64-tests
```

macOS presets 的最低部署目标为 macOS 11.0。

## 构建脚本

脚本会自动检测当前平台和架构：

```bash
./scripts/build-unix.sh
./scripts/build-unix.sh --rebuild
```

也可显式指定平台：

```bash
./scripts/build-unix.sh --platform linux-x64
./scripts/build-unix.sh --platform macos-arm64
./scripts/build-unix.sh --platform macos-x64
```

脚本不支持跨操作系统编译：Linux 包必须在 Linux 上构建，macOS 包必须在 macOS 上构建。macOS 主机可通过对应 preset 分别构建 arm64 和 x64。

## 发布脚本

运行：

```bash
./scripts/release-unix.sh
```

脚本自动完成：

1. 检测平台和架构。
2. Release 构建。
3. 执行跨平台 CTest 冒烟测试。
4. 校验 EXE、CMake 和 vcpkg manifest 版本一致。
5. 收集可执行文件、README、项目许可证和第三方许可证。
6. 生成 `tar.gz` 发布包和外部 SHA-256 文件。
7. 校验压缩包必要文件。

可选参数：

```bash
./scripts/release-unix.sh --skip-rebuild
./scripts/release-unix.sh --keep-staging
./scripts/release-unix.sh --output-directory ./dist-test
./scripts/release-unix.sh --platform linux-x64
```

发布产物：

```text
dist/econv-<version>-linux-x64.tar.gz
dist/econv-<version>-linux-x64.tar.gz.sha256
dist/econv-<version>-macos-arm64.tar.gz
dist/econv-<version>-macos-arm64.tar.gz.sha256
dist/econv-<version>-macos-x64.tar.gz
dist/econv-<version>-macos-x64.tar.gz.sha256
```

## 发布检查

Linux：

```bash
file build/linux-x64-vcpkg/econv
ldd build/linux-x64-vcpkg/econv
```

macOS：

```bash
file build/macos-arm64-vcpkg/econv
otool -L build/macos-arm64-vcpkg/econv
```

面向公网发布 macOS 包时，还应配置 Developer ID 签名和 Apple notarization；当前脚本不执行签名或公证。
