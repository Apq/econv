#if __has_include(<uchardet.h>)
#include <uchardet.h>
#elif __has_include(<uchardet/uchardet.h>)
#include <uchardet/uchardet.h>
#else
#error "uchardet header not found"
#endif

#include <iconv.h>

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

namespace {

enum class FallbackMode {
    Strict,
    Ignore,
    Translit,
};

struct Options {
    std::string inputPath;
    std::string outputPath;
    std::string fromEncoding;
    std::string toEncoding;
    FallbackMode fallback = FallbackMode::Strict;
    bool detectOnly = false;
    bool emitBom = false;
};

struct DetectionResult {
    std::string encoding;
    std::string method;
    std::size_t bomSize = 0;
};

void set_binary_stdio() {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
}

[[noreturn]] void fail(const std::string& message) {
    throw std::runtime_error(message);
}

std::string lower_ascii(std::string value) {
    for (char& ch : value) {
        ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    }
    return value;
}

std::string normalized_encoding_name(std::string value) {
    value = lower_ascii(std::move(value));
    std::string out;
    out.reserve(value.size());
    for (char ch : value) {
        if (ch != '-' && ch != '_' && ch != ' ') {
            out.push_back(ch);
        }
    }
    return out;
}

void print_help(std::ostream& os) {
    os << "econv - detect text encoding with uchardet and convert with iconv\n\n"
       << "Usage:\n"
       << "  econv --detect-only [-i input]\n"
       << "  econv [-i input] [-o output] [-f source-encoding] -t target-encoding [options]\n\n"
       << "Options:\n"
       << "  -i, --input <path>       input file, defaults to stdin\n"
       << "  -o, --output <path>      output file, defaults to stdout\n"
       << "  -f, --from <encoding>    force source encoding instead of auto-detecting\n"
       << "  -t, --to <encoding>      target encoding, required unless --detect-only is used\n"
       << "      --detect-only        print detected encoding and exit\n"
       << "      --fallback <mode>    strict, ignore, or translit; default: strict\n"
       << "      --emit-bom           prepend BOM for explicit UTF target encodings\n"
       << "  -h, --help               show this help\n";
}

FallbackMode parse_fallback(std::string_view value) {
    const std::string mode = lower_ascii(std::string(value));
    if (mode == "strict") {
        return FallbackMode::Strict;
    }
    if (mode == "ignore") {
        return FallbackMode::Ignore;
    }
    if (mode == "translit" || mode == "transliterate") {
        return FallbackMode::Translit;
    }
    fail("invalid fallback mode: " + std::string(value));
}

Options parse_args(int argc, char** argv) {
    Options options;

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        auto require_value = [&](const std::string& name) -> std::string {
            if (i + 1 >= argc) {
                fail("missing value for " + name);
            }
            return argv[++i];
        };

        if (arg == "-h" || arg == "--help") {
            print_help(std::cout);
            std::exit(0);
        } else if (arg == "-i" || arg == "--input") {
            options.inputPath = require_value(arg);
        } else if (arg == "-o" || arg == "--output") {
            options.outputPath = require_value(arg);
        } else if (arg == "-f" || arg == "--from") {
            options.fromEncoding = require_value(arg);
        } else if (arg == "-t" || arg == "--to") {
            options.toEncoding = require_value(arg);
        } else if (arg == "--fallback") {
            options.fallback = parse_fallback(require_value(arg));
        } else if (arg == "--detect-only") {
            options.detectOnly = true;
        } else if (arg == "--emit-bom") {
            options.emitBom = true;
        } else {
            fail("unknown argument: " + arg);
        }
    }

    if (!options.detectOnly && options.toEncoding.empty()) {
        fail("target encoding is required; pass -t/--to or use --detect-only");
    }
    return options;
}

std::vector<unsigned char> read_all_stdin() {
    std::istreambuf_iterator<char> begin(std::cin.rdbuf());
    std::istreambuf_iterator<char> end;
    std::vector<unsigned char> data;
    for (auto it = begin; it != end; ++it) {
        data.push_back(static_cast<unsigned char>(*it));
    }
    return data;
}

std::vector<unsigned char> read_file(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        fail("failed to open input file: " + path.string());
    }
    std::vector<unsigned char> data;
    file.unsetf(std::ios::skipws);
    file.seekg(0, std::ios::end);
    const std::streamoff size = file.tellg();
    if (size > 0) {
        data.reserve(static_cast<std::size_t>(size));
    }
    file.seekg(0, std::ios::beg);
    std::istream_iterator<unsigned char> begin(file);
    std::istream_iterator<unsigned char> end;
    data.assign(begin, end);
    return data;
}

std::vector<unsigned char> read_input(const Options& options) {
    if (options.inputPath.empty() || options.inputPath == "-") {
        return read_all_stdin();
    }
    return read_file(options.inputPath);
}

std::optional<DetectionResult> detect_bom(const std::vector<unsigned char>& data) {
    auto starts_with = [&](std::initializer_list<unsigned char> prefix) {
        if (data.size() < prefix.size()) {
            return false;
        }
        std::size_t index = 0;
        for (unsigned char byte : prefix) {
            if (data[index++] != byte) {
                return false;
            }
        }
        return true;
    };

    if (starts_with({0x00, 0x00, 0xFE, 0xFF})) {
        return DetectionResult{"UTF-32BE", "bom", 4};
    }
    if (starts_with({0xFF, 0xFE, 0x00, 0x00})) {
        return DetectionResult{"UTF-32LE", "bom", 4};
    }
    if (starts_with({0xEF, 0xBB, 0xBF})) {
        return DetectionResult{"UTF-8", "bom", 3};
    }
    if (starts_with({0xFE, 0xFF})) {
        return DetectionResult{"UTF-16BE", "bom", 2};
    }
    if (starts_with({0xFF, 0xFE})) {
        return DetectionResult{"UTF-16LE", "bom", 2};
    }
    return std::nullopt;
}

bool is_valid_utf8(const std::vector<unsigned char>& data, std::size_t offset) {
    std::size_t i = offset;
    while (i < data.size()) {
        const unsigned char c = data[i];
        if (c <= 0x7F) {
            ++i;
            continue;
        }

        std::uint32_t codepoint = 0;
        std::size_t extra = 0;
        if ((c & 0xE0) == 0xC0) {
            codepoint = c & 0x1F;
            extra = 1;
            if (codepoint == 0) {
                return false;
            }
        } else if ((c & 0xF0) == 0xE0) {
            codepoint = c & 0x0F;
            extra = 2;
        } else if ((c & 0xF8) == 0xF0) {
            codepoint = c & 0x07;
            extra = 3;
        } else {
            return false;
        }

        if (i + extra >= data.size()) {
            return false;
        }

        for (std::size_t j = 1; j <= extra; ++j) {
            const unsigned char cc = data[i + j];
            if ((cc & 0xC0) != 0x80) {
                return false;
            }
            codepoint = (codepoint << 6) | (cc & 0x3F);
        }

        if ((extra == 1 && codepoint < 0x80) ||
            (extra == 2 && codepoint < 0x800) ||
            (extra == 3 && codepoint < 0x10000)) {
            return false;
        }
        if (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
            return false;
        }
        if (codepoint > 0x10FFFF) {
            return false;
        }

        i += extra + 1;
    }
    return true;
}

bool iconv_can_open(const std::string& toEncoding, const std::string& fromEncoding) {
    iconv_t cd = iconv_open(toEncoding.c_str(), fromEncoding.c_str());
    if (cd == reinterpret_cast<iconv_t>(-1)) {
        return false;
    }
    iconv_close(cd);
    return true;
}

DetectionResult detect_with_uchardet(const std::vector<unsigned char>& data) {
    uchardet_t detector = uchardet_new();
    if (!detector) {
        fail("uchardet_new failed");
    }

    if (!data.empty()) {
        const auto* bytes = reinterpret_cast<const char*>(data.data());
        if (uchardet_handle_data(detector, bytes, data.size()) != 0) {
            uchardet_delete(detector);
            fail("uchardet failed to handle input data");
        }
    }
    uchardet_data_end(detector);

    const char* detected = uchardet_get_charset(detector);
    std::string encoding = detected ? detected : "";
    uchardet_delete(detector);

    if (encoding.empty()) {
        fail("could not detect source encoding; pass --from explicitly");
    }
    if (!iconv_can_open("UTF-8", encoding)) {
        fail("uchardet detected unsupported source encoding for iconv: " + encoding);
    }
    return DetectionResult{encoding, "uchardet", 0};
}

DetectionResult detect_encoding(const std::vector<unsigned char>& data) {
    if (auto bom = detect_bom(data)) {
        return *bom;
    }
    if (is_valid_utf8(data, 0)) {
        return DetectionResult{"UTF-8", "utf8-validate", 0};
    }
    return detect_with_uchardet(data);
}

std::string with_fallback_suffix(const std::string& target, FallbackMode fallback) {
    if (target.find("//") != std::string::npos) {
        return target;
    }
    switch (fallback) {
        case FallbackMode::Strict:
            return target;
        case FallbackMode::Ignore:
            return target + "//IGNORE";
        case FallbackMode::Translit:
            return target + "//TRANSLIT";
    }
    return target;
}

std::string errno_message(const std::string& context) {
#ifdef _MSC_VER
    char buffer[256] = {};
    strerror_s(buffer, sizeof(buffer), errno);
    return context + ": " + buffer;
#else
    return context + ": " + std::strerror(errno);
#endif
}

std::vector<unsigned char> convert_encoding(
    const std::vector<unsigned char>& input,
    std::size_t offset,
    const std::string& fromEncoding,
    const std::string& toEncoding,
    FallbackMode fallback) {

    const std::string target = with_fallback_suffix(toEncoding, fallback);
    iconv_t cd = iconv_open(target.c_str(), fromEncoding.c_str());
    if (cd == reinterpret_cast<iconv_t>(-1)) {
        fail(errno_message("iconv_open failed for " + fromEncoding + " -> " + target));
    }

    std::size_t inLeft = input.size() - offset;
    char* inPtr = const_cast<char*>(reinterpret_cast<const char*>(input.data() + offset));
    std::vector<unsigned char> output;
    output.resize(std::max<std::size_t>(4096, inLeft * 4 + 32));
    char* outPtr = reinterpret_cast<char*>(output.data());
    std::size_t outLeft = output.size();

    auto produced = [&]() -> std::size_t {
        return static_cast<std::size_t>(outPtr - reinterpret_cast<char*>(output.data()));
    };

    auto grow = [&]() {
        const std::size_t used = produced();
        output.resize(output.size() * 2 + 4096);
        outPtr = reinterpret_cast<char*>(output.data()) + used;
        outLeft = output.size() - used;
    };

    while (inLeft > 0) {
        errno = 0;
        const std::size_t rc = iconv(cd, &inPtr, &inLeft, &outPtr, &outLeft);
        if (rc != static_cast<std::size_t>(-1)) {
            continue;
        }
        if (errno == E2BIG) {
            grow();
            continue;
        }
        const std::size_t inputOffset = input.size() - offset - inLeft;
        iconv_close(cd);
        if (errno == EINVAL) {
            fail("incomplete multibyte sequence near input offset " + std::to_string(inputOffset));
        }
        if (errno == EILSEQ) {
            fail("invalid or unconvertible sequence near input offset " + std::to_string(inputOffset));
        }
        fail(errno_message("iconv conversion failed near input offset " + std::to_string(inputOffset)));
    }

    while (true) {
        errno = 0;
        const std::size_t rc = iconv(cd, nullptr, nullptr, &outPtr, &outLeft);
        if (rc != static_cast<std::size_t>(-1)) {
            break;
        }
        if (errno == E2BIG) {
            grow();
            continue;
        }
        iconv_close(cd);
        fail(errno_message("iconv flush failed"));
    }

    iconv_close(cd);
    output.resize(produced());
    return output;
}

std::vector<unsigned char> bom_for_target(const std::string& encoding) {
    const std::string name = normalized_encoding_name(encoding);
    if (name == "utf8") {
        return {0xEF, 0xBB, 0xBF};
    }
    if (name == "utf16le") {
        return {0xFF, 0xFE};
    }
    if (name == "utf16be") {
        return {0xFE, 0xFF};
    }
    if (name == "utf32le") {
        return {0xFF, 0xFE, 0x00, 0x00};
    }
    if (name == "utf32be") {
        return {0x00, 0x00, 0xFE, 0xFF};
    }
    return {};
}

void write_output(const Options& options, const std::vector<unsigned char>& bytes) {
    if (options.outputPath.empty() || options.outputPath == "-") {
        std::cout.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        return;
    }

    std::ofstream file(options.outputPath, std::ios::binary);
    if (!file) {
        fail("failed to open output file: " + options.outputPath);
    }
    file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
}

void print_detection(const DetectionResult& detection) {
    std::cout << "encoding: " << detection.encoding << '\n'
              << "method: " << detection.method << '\n'
              << "source-bom-bytes: " << detection.bomSize << '\n';
}

int run(int argc, char** argv) {
    set_binary_stdio();
    const Options options = parse_args(argc, argv);
    const std::vector<unsigned char> input = read_input(options);

    DetectionResult detection;
    if (!options.fromEncoding.empty()) {
        detection = DetectionResult{options.fromEncoding, "user", 0};
    } else {
        detection = detect_encoding(input);
    }

    if (options.detectOnly) {
        print_detection(detection);
        return 0;
    }

    std::vector<unsigned char> output = convert_encoding(
        input,
        detection.bomSize,
        detection.encoding,
        options.toEncoding,
        options.fallback);

    if (options.emitBom) {
        std::vector<unsigned char> bom = bom_for_target(options.toEncoding);
        if (!bom.empty()) {
            bom.insert(bom.end(), output.begin(), output.end());
            output.swap(bom);
        }
    }

    write_output(options, output);
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        return run(argc, argv);
    } catch (const std::exception& ex) {
        std::cerr << "econv: " << ex.what() << '\n';
        return 1;
    }
}
