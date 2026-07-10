# Third-Party Notices

`econv` uses uchardet and an iconv implementation. Release packages include the complete license texts for the third-party components redistributed in that package as `THIRD-PARTY-LICENSES.txt`.

## uchardet

- Purpose: legacy text encoding detection
- Source: https://gitlab.freedesktop.org/uchardet/uchardet
- Version used by vcpkg: 0.0.8
- License: Mozilla Public License 1.1

## iconv / GNU libiconv

- Purpose: character encoding conversion through the iconv API
- Homepage: https://www.gnu.org/software/libiconv/
- Source: https://git.savannah.gnu.org/git/libiconv.git
- Windows packages use GNU libiconv 1.19 from vcpkg. Its libiconv and libcharset libraries and headers are licensed under LGPL 2.1 or later; the standalone iconv program and documentation are licensed under GPL.
- Linux and macOS packages use the iconv implementation provided by the target operating system and do not redistribute GNU libiconv.

Each release package combines the applicable license and copyright files for its redistributed dependencies into one file.
