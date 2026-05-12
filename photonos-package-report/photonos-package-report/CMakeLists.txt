cmake_minimum_required(VERSION 3.18)
project(photonos-package-report C)

# ----- ADR-0001 (C11) + ADR-0008 (Photon-only) ----------------------
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Photon ships these as RPMs. The maintainer-side install command is:
#   tdnf install -y cmake gcc libcurl-devel pcre2-devel json-c-devel libarchive-devel pkg-config
# Phase 1 only used libc + pthread; Phase 2 adds PCRE2 for Get-SpecValue.
find_package(PkgConfig REQUIRED)
pkg_check_modules(PCRE2 REQUIRED libpcre2-8)

# ----- Phase 1 + 2 executable ---------------------------------------
add_executable(photonos-package-report
    src/main.c
    src/convert.c
    src/diskspace.c
    src/git_with_timeout.c
    src/task.c
    src/spec_value.c
    src/parse_directory.c
)

target_include_directories(photonos-package-report PRIVATE include ${PCRE2_INCLUDE_DIRS})
target_link_libraries(photonos-package-report PRIVATE pthread ${PCRE2_LIBRARIES})
target_compile_options(photonos-package-report PRIVATE -Wall -Wextra -O2 -D_GNU_SOURCE ${PCRE2_CFLAGS_OTHER})

# ----- Tests --------------------------------------------------------
enable_testing()
add_subdirectory(tests/unit)
