add_executable(test_phase1
    test_phase1.c
    ${CMAKE_SOURCE_DIR}/src/convert.c
    ${CMAKE_SOURCE_DIR}/src/diskspace.c
    ${CMAKE_SOURCE_DIR}/src/git_with_timeout.c
)
target_include_directories(test_phase1 PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_phase1 PRIVATE pthread)
target_compile_options(test_phase1 PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE)

add_test(NAME test_phase1 COMMAND test_phase1)

# ----- Phase 2 unit tests (Get-SpecValue + ParseDirectory) -----------
add_executable(test_phase2
    test_phase2.c
    ${CMAKE_SOURCE_DIR}/src/task.c
    ${CMAKE_SOURCE_DIR}/src/spec_value.c
    ${CMAKE_SOURCE_DIR}/src/parse_directory.c
)
target_include_directories(test_phase2 PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${PCRE2_INCLUDE_DIRS}
)
target_link_libraries(test_phase2 PRIVATE pthread ${PCRE2_LIBRARIES})
target_compile_options(test_phase2 PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE ${PCRE2_CFLAGS_OTHER})

add_test(NAME test_phase2 COMMAND test_phase2
    "${CMAKE_SOURCE_DIR}/tests/fixtures")

# ----- Phase 3 unit tests (Source0Lookup CSV embed) -----------------
add_executable(test_phase3
    test_phase3.c
    ${CMAKE_SOURCE_DIR}/src/source0_lookup.c
)
add_dependencies(test_phase3 pr-source0-lookup-data)
target_include_directories(test_phase3 PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${PR_GEN_DIR}
)
target_compile_options(test_phase3 PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE)

add_test(NAME test_phase3 COMMAND test_phase3)

# The byte-identical-against-PS-source parity test was removed: the PS
# embed contains stylistic quoting (`"trunk"` etc.) that has no effect
# on `ConvertFrom-Csv` output and therefore none on the .prn outputs the
# real parity gate cares about. test_phase3 instead validates SEMANTIC
# parity (per-field) and an emit→re-parse roundtrip.
#
# tests/parity/source0-lookup-roundtrip.sh remains in the tree as a
# diagnostic tool (callable manually) and as a placeholder for the
# Phase 8 end-to-end .prn parity harness.
