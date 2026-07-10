# econv

`econv` 是一个小型跨平台命令行工具，用于通过 `uchardet` 检测文本编码，并通过 `iconv`/`libiconv` 将文本转换为另一种编码。

对传统编码的检测具有概率性。`econv` 会先处理确定性的情况（BOM 和严格 UTF-8 校验），然后再回退到 `uchardet`。如果你已经知道源文件编码，或者低置信度的传统编码文件被误判，请使用 `--from` 指定源编码。

## 功能

- 在使用启发式检测前先识别 UTF BOM。
- 将结构上合法的 UTF-8 文本视为 UTF-8。
- 使用 `uchardet` 检测传统编码。
- 使用 `iconv`/`libiconv` 转换为任意受支持的目标编码。
- 支持文件输入输出以及 stdin/stdout。
- 支持严格、忽略和音译三种回退模式。
- 支持为显式 UTF 目标编码输出可选 BOM。

## 依赖

- CMake 3.20+
- C++17 编译器
- uchardet 开发包
- iconv 实现

Linux 通常在 libc 中提供 iconv。macOS 提供系统 iconv，也可以使用 Homebrew 的 `libiconv`。Windows 构建建议使用 vcpkg、MSYS2 或其他同时提供 uchardet 和 libiconv 的包管理器。

## 构建

Windows 推荐使用 vcpkg manifest 和 CMake Presets。先设置 `VCPKG_ROOT` 指向 vcpkg 安装目录，例如 Visual Studio 自带的 vcpkg：

```powershell
$env:VCPKG_ROOT = "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\vcpkg"
cmake --preset windows-msvc-vcpkg
cmake --build --preset windows-debug
```

使用系统软件包构建：

```bash
cmake -S . -B build
cmake --build build --config Release
```

使用 vcpkg 手动指定 toolchain：

```bash
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=/path/to/vcpkg/scripts/buildsystems/vcpkg.cmake
cmake --build build --config Release
```

## 调试

仓库包含 VS Code 调试配置。打开项目后选择 `Debug econv (--help)`，会先构建 Debug 版本，再用 MSVC 调试器启动 `econv.exe`。

Windows 下生成 Visual Studio 项目、解决方案和 VS Code 调试的完整步骤见 [Windows 构建与调试](docs/windows-build.md)。

## 测试

冒烟测试使用 CMake/CTest 驱动和仓库内固定编码样本，可在 Windows、Linux 和 macOS 上运行，不依赖 PowerShell：

```powershell
cmake --build --preset windows-debug
ctest --test-dir build/windows-msvc-vcpkg -C Debug --output-on-failure
```

Unix 平台构建后可使用对应 test preset，例如：

```bash
ctest --preset linux-x64-tests
ctest --preset macos-arm64-tests
```

## 版本管理与编译脚本

项目版本格式为 `Major.Minor.Year.MMDD`，例如 `0.1.2026.710`。版本同时写入 CMake、vcpkg manifest 和 Windows EXE 文件属性。

```powershell
# 设置主版本和次版本，日期部分自动使用当天日期
.\scripts\set-version.ps1 0 2

# 次版本加 1，日期部分自动使用当天日期
.\scripts\bump-version.ps1

# 构建 Release（默认）
.\scripts\build.ps1

# 构建 Debug 或执行全量重建
.\scripts\build.ps1 -Configuration Debug
.\scripts\build.ps1 -Rebuild

# 构建、测试并生成 Windows x64 发布 ZIP
.\scripts\release.ps1
```

对应的 `.bat` 文件可以直接双击或在命令行调用。版本脚本支持 `-DryRun` 预览，不修改文件。

发布脚本会把 ZIP 和 SHA-256 校验文件生成到 `dist/`，其中包含 EXE、运行时 DLL、README、项目许可证、第三方声明和合并后的第三方许可证。使用 `-SkipRebuild` 可跳过全量重建，使用 `-KeepStaging` 可保留打包暂存目录，使用 `-OutputDirectory <path>` 可指定输出目录。

发布包中的 `add-to-path.bat` 总会将发布目录添加到当前用户 `PATH`；如果它已经以管理员权限运行，还会同时添加到系统 `PATH`。脚本不会主动请求提权，更新后需要重新打开终端。执行 `add-to-path.bat --dry-run` 可预览操作而不修改任何 PATH。

Linux/macOS 的构建、测试和 `tar.gz` 发布方式见 [Unix 构建与发布](docs/unix-build.md)。

## GitHub 发布

仓库通过 GitHub Actions 在 Windows x64、Linux x64、macOS arm64 和 macOS x64 上执行 Release 构建、CTest 冒烟测试和发布包校验。工作流仅在以下情况运行：

- 推送 `v<版本>` 格式的数字版本标签，例如 `v0.1` 或 `v0.1.2026.710`。
- 在 Actions 页面手动运行。

推送版本标签时，工作流构建该标签指向的源码并发布对应的 GitHub Release，例如：

```bash
git tag v0.1
git push origin v0.1
```

手动运行时，请将 GitHub 的 `Use workflow from` 保持为包含工作流的分支（通常是 `master`），并在 `发布标签` 输入框中指定版本标签。输入框留空时，工作流按版本顺序选择仓库中最大的有效版本标签；如果仓库还没有版本标签，则使用 `v0.1`。手动运行始终以 `Use workflow from` 中选择的 ref 作为源码，发布标签只决定 GitHub Release 版本。

GitHub 只有在所选 ref 本身包含工作流文件时才能手动运行该工作流。因此，早于工作流创建的旧标签（例如当前的 `v0.1`）不能直接用于 `Use workflow from`；应从 `master` 启动，并在 `发布标签` 输入框中填写 `v0.1`。

工作流会等待四个平台全部构建和测试通过，然后创建或更新 GitHub Release，自动生成发布说明，并上传各平台压缩包及其 SHA-256 校验文件。压缩包文件名仍使用 `CMakeLists.txt` 和 `vcpkg.json` 中的完整项目版本。

## 用法

仅检测编码：

```bash
econv --detect-only -i input.txt
```

自动检测并转换为 UTF-8：

```bash
econv -i input.txt -o output.txt -t UTF-8
```

强制指定源编码并转换为 GB18030：

```bash
econv -i input.txt -o output.txt --from SHIFT_JIS --to GB18030
```

使用 stdin/stdout：

```bash
cat input.txt | econv --to UTF-8 > output.txt
```

当目标编码无法表示某些字符时，允许有损转换：

```bash
econv -i input.txt -o output.txt -t ISO-8859-1 --fallback translit
econv -i input.txt -o output.txt -t ISO-8859-1 --fallback ignore
```

## 选项

```text
  -i, --input <path>       输入文件，默认为 stdin
  -o, --output <path>      输出文件，默认为 stdout
  -f, --from <encoding>    强制指定源编码，而不是自动检测
  -t, --to <encoding>      目标编码；除非使用 --detect-only，否则必填
      --detect-only        打印检测到的编码并退出
      --fallback <mode>    strict、ignore 或 translit；默认值：strict
      --emit-bom           为 UTF-8/UTF-16LE/UTF-16BE/UTF-32LE/UTF-32BE 添加 BOM 前缀
      --version            显示版本号
  -h, --help               显示帮助
```

目标编码和源编码名称会直接传给 `iconv`，因此支持的名称取决于当前平台的 iconv 实现。
