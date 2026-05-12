cmake_minimum_required(VERSION 3.18)
project(photonos-package-report C)

# ----- ADR-0001 (C11) + ADR-0008 (Photon-only) ----------------------
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Photon ships these as RPMs. The maintainer-side install command is:
#   tdnf install -y cmake gcc libcurl-devel pcre2-devel json-c-devel libarchive-devel pkg-config
# Phase 1 only uses libc + pthread; later phases add libcurl/pcre2/json-c/libarchive.
find_package(PkgConfig REQUIRED)

# ----- Phase 1 executable -------------------------------------------
add_executable(photonos-package-report
    src/main.c
    src/convert.c
    src/diskspace.c
    src/git_with_timeout.c
)

target_include_directories(photonos-package-report PRIVATE include)
target_link_libraries(photonos-package-report PRIVATE pthread)
target_compile_options(photonos-package-report PRIVATE -Wall -Wextra -O2 -D_GNU_SOURCE)

# ----- Tests --------------------------------------------------------
enable_testing()
add_subdirectory(tests/unit)
