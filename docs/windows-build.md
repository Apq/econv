# Windows 构建与调试

本文档说明如何在 Windows 上用 vcpkg、CMake 和 Visual Studio 生成项目文件、解决方案文件并启动调试。

## 前置条件

- Visual Studio 2026，安装 C++ 桌面开发工作负载
- CMake 3.20+
- vcpkg

如果使用 Visual Studio 自带的 vcpkg，路径通常是：

```powershell
C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\vcpkg
```

## 生成 VS 项目和解决方案

在仓库根目录执行：

```powershell
$env:VCPKG_ROOT = "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\vcpkg"
cmake --preset windows-msvc-vcpkg
```

CMake 会自动读取 `vcpkg.json`，安装或恢复 `uchardet`、`libiconv` 等依赖，并在下面的目录生成 Visual Studio 文件：

```text
build/windows-msvc-vcpkg/
```

主要生成文件：

```text
build/windows-msvc-vcpkg/econv.slnx
build/windows-msvc-vcpkg/econv.vcxproj
build/windows-msvc-vcpkg/econv.vcxproj.filters
```

说明：Visual Studio 18 / CMake 4.4 会生成新的 `.slnx` 解决方案格式，而不是传统 `.sln`。

## 构建 Debug 和 Release

Debug：

```powershell
cmake --build --preset windows-debug
```

Release：

```powershell
cmake --build --preset windows-release
```

生成的可执行文件位置：

```text
build/windows-msvc-vcpkg/Debug/econv.exe
build/windows-msvc-vcpkg/Release/econv.exe
```

也可以使用仓库提供的编译脚本：

```powershell
.\scripts\build.ps1
.\scripts\build.ps1 -Configuration Debug
.\scripts\build.ps1 -Rebuild
```

`scripts/build.bat` 是对应的批处理入口。脚本会自动使用 `VCPKG_ROOT`，未设置时尝试查找 Visual Studio 自带的 vcpkg。

## 版本管理

版本格式为 `Major.Minor.Year.MMDD`，例如 `0.1.2026.710`。版本号会写入：

```text
CMakeLists.txt
vcpkg.json
econv.exe 的 Windows 文件版本信息
```

设置主版本和次版本：

```powershell
.\scripts\set-version.ps1 0 2
```

次版本自动加 1：

```powershell
.\scripts\bump-version.ps1
```

日期部分由脚本按当天日期自动生成。两个脚本均支持 `-DryRun`，对应的 `.bat` 文件可直接调用。

## 用 Visual Studio 打开

可以直接打开生成的解决方案文件：

```powershell
devenv .\build\windows-msvc-vcpkg\econv.slnx
```

也可以在资源管理器中双击：

```text
build/windows-msvc-vcpkg/econv.slnx
```

## 用 VS Code 调试

仓库已包含 VS Code 配置：

```text
.vscode/tasks.json
.vscode/launch.json
```

步骤：

1. 在 VS Code 中打开仓库根目录。
2. 确认当前终端或用户环境变量中已设置 `VCPKG_ROOT`。
3. 打开“运行和调试”。
4. 选择 `Debug econv (--help)`。
5. 按 `F5`。

该调试配置会先执行 `cmake --preset windows-msvc-vcpkg`，再执行 `cmake --build --preset windows-debug`，最后启动：

```text
build/windows-msvc-vcpkg/Debug/econv.exe --help
```

如果要调试其他参数，修改 `.vscode/launch.json` 中的 `args`。

## 哪些文件不提交

下面这些目录和文件是本地生成物或本机配置，不提交到 Git：

```text
build/
build-*/
cmake-build-*/
CMakeUserPresets.json
.vs/
20??-??-??.json
```

原因：

- `build/` 和 `build-*` 里是 CMake/VS/vcpkg 生成物，包含 `.slnx`、`.vcxproj`、exe、pdb、依赖库和缓存。
- `CMakeUserPresets.json` 通常包含本机绝对路径，不适合提交。
- `.vs/` 是 Visual Studio 本地状态。
- `20??-??-??.json` 是本地会话导出文件，不属于项目源码。

Git 仓库中应该提交的是生成这些文件的配置：

```text
CMakeLists.txt
CMakePresets.json
vcpkg.json
.vscode/tasks.json
.vscode/launch.json
```
