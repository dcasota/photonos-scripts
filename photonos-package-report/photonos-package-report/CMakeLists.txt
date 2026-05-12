cmake_minimum_required(VERSION 3.18)
project(photonos-package-report C)

# ----- ADR-0001 (C11) + ADR-0008 (Photon-only) ----------------------
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Photon ships these as RPMs. The maintainer-side install command is:
#   tdnf install -y cmake gcc libcurl-devel pcre2-devel json-c-devel libarchive-devel pkg-config
# Phase 1 used libc + pthread; Phase 2 added PCRE2; Phase 3 adds the
# bash+awk Source0LookupData generator (no extra runtime deps).
find_package(PkgConfig REQUIRED)
pkg_check_modules(PCRE2 REQUIRED libpcre2-8)

# ----- Phase 3 generator: embedded Source0LookupData CSV -------------
# Runs at build time. Output lives under ${CMAKE_BINARY_DIR}/generated
# and is NOT committed (ADR-0005 + source0-lookup-embedder agent spec).
set(PR_PS_UPSTREAM ${CMAKE_SOURCE_DIR}/../photonos-package-report.ps1)
set(PR_GEN_DIR     ${CMAKE_BINARY_DIR}/generated)
set(PR_GEN_HEADER  ${PR_GEN_DIR}/source0_lookup_data.h)

file(MAKE_DIRECTORY ${PR_GEN_DIR})
add_custom_command(
    OUTPUT  ${PR_GEN_HEADER}
    COMMAND ${CMAKE_COMMAND} -E echo "Regenerating ${PR_GEN_HEADER}"
    COMMAND sh -c
        "'${CMAKE_SOURCE_DIR}/tools/extract-source0-lookup.sh' '${PR_PS_UPSTREAM}' \
         | '${CMAKE_SOURCE_DIR}/tools/csv-to-c-string.sh' \
         > '${PR_GEN_HEADER}'"
    DEPENDS
        ${PR_PS_UPSTREAM}
        ${CMAKE_SOURCE_DIR}/tools/extract-source0-lookup.sh
        ${CMAKE_SOURCE_DIR}/tools/csv-to-c-string.sh
    VERBATIM
    COMMENT "Extracting embedded Source0LookupData CSV from upstream PS script"
)

add_custom_target(pr-source0-lookup-data DEPENDS ${PR_GEN_HEADER})

# ----- Phase 1 + 2 + 3 executable -----------------------------------
add_executable(photonos-package-report
    src/main.c
    src/convert.c
    src/diskspace.c
    src/git_with_timeout.c
    src/task.c
    src/spec_value.c
    src/parse_directory.c
    src/source0_lookup.c
)

add_dependencies(photonos-package-report pr-source0-lookup-data)

target_include_directories(photonos-package-report PRIVATE
    include
    ${PR_GEN_DIR}
    ${PCRE2_INCLUDE_DIRS}
)
target_link_libraries(photonos-package-report PRIVATE pthread ${PCRE2_LIBRARIES})
target_compile_options(photonos-package-report PRIVATE -Wall -Wextra -O2 -D_GNU_SOURCE ${PCRE2_CFLAGS_OTHER})

# ----- Tests --------------------------------------------------------
enable_testing()
add_subdirectory(tests/unit)
