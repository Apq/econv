cmake_minimum_required(VERSION 3.20)

if(NOT DEFINED ECONV_EXE OR NOT EXISTS "${ECONV_EXE}")
  message(FATAL_ERROR "ECONV_EXE does not exist: ${ECONV_EXE}")
endif()
if(NOT DEFINED FIXTURE_DIR OR NOT IS_DIRECTORY "${FIXTURE_DIR}")
  message(FATAL_ERROR "FIXTURE_DIR does not exist: ${FIXTURE_DIR}")
endif()
if(NOT DEFINED TEST_OUTPUT_DIR)
  set(TEST_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/smoke-test-output")
endif()

file(MAKE_DIRECTORY "${TEST_OUTPUT_DIR}")

function(run_success name)
  execute_process(
    COMMAND "${ECONV_EXE}" ${ARGN}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "${name} failed (${result})\nstdout:\n${stdout}\nstderr:\n${stderr}")
  endif()
  set(LAST_STDOUT "${stdout}" PARENT_SCOPE)
  set(LAST_STDERR "${stderr}" PARENT_SCOPE)
endfunction()

function(assert_contains name text expected)
  string(FIND "${text}" "${expected}" position)
  if(position EQUAL -1)
    message(FATAL_ERROR "${name}: expected '${expected}' in:\n${text}")
  endif()
endfunction()

function(assert_same_file name expected actual)
  file(SHA256 "${expected}" expected_hash)
  file(SHA256 "${actual}" actual_hash)
  if(NOT expected_hash STREQUAL actual_hash)
    message(FATAL_ERROR "${name}: files differ\nexpected: ${expected}\nactual: ${actual}")
  endif()
endfunction()

run_success("version" --version)
assert_contains("version" "${LAST_STDOUT}" "econv ")

foreach(case IN ITEMS utf8 utf8-bom utf16le-bom)
  run_success("detect ${case}" --detect-only -i "${FIXTURE_DIR}/${case}.bin")
  if(case STREQUAL "utf16le-bom")
    assert_contains("detect ${case}" "${LAST_STDOUT}" "encoding: UTF-16LE")
  else()
    assert_contains("detect ${case}" "${LAST_STDOUT}" "encoding: UTF-8")
  endif()
endforeach()

run_success(
  "detect GB18030 with explicit source encoding"
  --detect-only --from GB18030 -i "${FIXTURE_DIR}/gb18030.bin")
assert_contains("detect GB18030" "${LAST_STDOUT}" "encoding: GB18030")
assert_contains("detect GB18030" "${LAST_STDOUT}" "method: user")

run_success(
  "convert GB18030 to UTF-8"
  -i "${FIXTURE_DIR}/gb18030.bin"
  -o "${TEST_OUTPUT_DIR}/gb18030-to-utf8.bin"
  --from GB18030 --to UTF-8)
assert_same_file(
  "convert GB18030 to UTF-8"
  "${FIXTURE_DIR}/utf8.bin"
  "${TEST_OUTPUT_DIR}/gb18030-to-utf8.bin")

run_success(
  "convert UTF-16LE BOM to UTF-8"
  -i "${FIXTURE_DIR}/utf16le-bom.bin"
  -o "${TEST_OUTPUT_DIR}/utf16le-to-utf8.bin"
  --to UTF-8)
assert_same_file(
  "convert UTF-16LE BOM to UTF-8"
  "${FIXTURE_DIR}/utf8.bin"
  "${TEST_OUTPUT_DIR}/utf16le-to-utf8.bin")

run_success(
  "emit UTF-8 BOM"
  -i "${FIXTURE_DIR}/utf8.bin"
  -o "${TEST_OUTPUT_DIR}/utf8-emit-bom.bin"
  --to UTF-8 --emit-bom)
file(READ "${TEST_OUTPUT_DIR}/utf8-emit-bom.bin" bom_hex HEX LIMIT 3)
string(TOLOWER "${bom_hex}" bom_hex)
if(NOT bom_hex STREQUAL "efbbbf")
  message(FATAL_ERROR "emit UTF-8 BOM: expected efbbbf, got ${bom_hex}")
endif()

execute_process(
  COMMAND "${ECONV_EXE}"
    -i "${FIXTURE_DIR}/utf8.bin"
    -o "${TEST_OUTPUT_DIR}/utf8-to-latin1-strict.bin"
    --to ISO-8859-1
  RESULT_VARIABLE strict_result
  OUTPUT_VARIABLE strict_stdout
  ERROR_VARIABLE strict_stderr)
if(strict_result EQUAL 0)
  message(FATAL_ERROR "strict conversion unexpectedly succeeded")
endif()
assert_contains("strict conversion" "${strict_stderr}" "invalid or unconvertible sequence")

message(STATUS "All econv smoke tests passed")
