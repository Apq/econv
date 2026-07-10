cmake_minimum_required(VERSION 3.20)

project(econv VERSION 0.1.2026.710 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(ECONV_SOURCES src/main.cpp)

if(WIN32)
  enable_language(RC)
  configure_file(src/version.rc.in version.rc @ONLY)
  list(APPEND ECONV_SOURCES "${CMAKE_CURRENT_BINARY_DIR}/version.rc")
endif()

add_executable(econv ${ECONV_SOURCES})
target_compile_definitions(econv PRIVATE ECONV_VERSION="${PROJECT_VERSION}")

enable_testing()

find_package(Iconv REQUIRED)

find_package(uchardet CONFIG QUIET)

if(uchardet_FOUND)
  set(UCHARDET_TARGET uchardet::libuchardet)
else()
  find_package(PkgConfig QUIET)
  if(PkgConfig_FOUND)
    pkg_check_modules(PC_UCHARDET QUIET uchardet)
  endif()

  find_path(UCHARDET_INCLUDE_DIR
    NAMES uchardet/uchardet.h uchardet.h
    HINTS ${PC_UCHARDET_INCLUDEDIR} ${PC_UCHARDET_INCLUDE_DIRS})

  find_library(UCHARDET_LIBRARY
    NAMES uchardet libuchardet
    HINTS ${PC_UCHARDET_LIBDIR} ${PC_UCHARDET_LIBRARY_DIRS})

  include(FindPackageHandleStandardArgs)
  find_package_handle_standard_args(UCHARDET
    REQUIRED_VARS UCHARDET_LIBRARY UCHARDET_INCLUDE_DIR)

  if(NOT TARGET UCHARDET::UCHARDET)
    add_library(UCHARDET::UCHARDET UNKNOWN IMPORTED)
    set_target_properties(UCHARDET::UCHARDET PROPERTIES
      IMPORTED_LOCATION "${UCHARDET_LIBRARY}"
      INTERFACE_INCLUDE_DIRECTORIES "${UCHARDET_INCLUDE_DIR}")
  endif()
  set(UCHARDET_TARGET UCHARDET::UCHARDET)
endif()

target_link_libraries(econv PRIVATE Iconv::Iconv ${UCHARDET_TARGET})

target_compile_options(econv PRIVATE
  $<$<CXX_COMPILER_ID:MSVC>:/W4>
  $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall -Wextra -Wpedantic>)

install(TARGETS econv RUNTIME DESTINATION bin)

if(WIN32)
  add_test(
    NAME manual-smoke
    COMMAND powershell -ExecutionPolicy Bypass -File "${CMAKE_SOURCE_DIR}/scripts/manual-test.ps1" -Configuration $<CONFIG>)
endif()
