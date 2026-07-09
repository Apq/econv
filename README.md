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

Windows 下先构建 Debug 版本，然后运行手工冒烟测试脚本：

```powershell
cmake --build --preset windows-debug
.\scripts\manual-test.ps1 -Configuration Debug
```

也可以通过 CTest 运行：

```powershell
ctest --test-dir build/windows-msvc-vcpkg -C Debug --output-on-failure
```

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
  -h, --help               显示帮助
```

目标编码和源编码名称会直接传给 `iconv`，因此支持的名称取决于当前平台的 iconv 实现。
