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
    ${CMAKE_SOURCE_DIR}/src/strutil.c
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

# ----- Phase 3b unit tests (per-spec hook dispatch) ------------------
# Mark the generated dispatch source as GENERATED so CMake doesn't try
# to validate its existence at configure time (it lands at build time
# via the pr-hook-dispatch custom target).
set_source_files_properties(${PR_GEN_HOOK_DISPATCH} PROPERTIES GENERATED TRUE)

add_executable(test_phase3b
    test_phase3b.c
    ${CMAKE_SOURCE_DIR}/src/hook_dispatch.c
    ${PR_GEN_HOOK_DISPATCH}
    ${PR_HOOK_SOURCES}
)
add_dependencies(test_phase3b pr-hook-dispatch)
target_include_directories(test_phase3b PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_compile_options(test_phase3b PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE)

add_test(NAME test_phase3b COMMAND test_phase3b)

# ----- Phase 4 unit tests (Source0 substitution core) ----------------
add_executable(test_phase4
    test_phase4.c
    ${CMAKE_SOURCE_DIR}/src/strutil.c
    ${CMAKE_SOURCE_DIR}/src/source0_substitute.c
    ${CMAKE_SOURCE_DIR}/src/task.c
)
target_include_directories(test_phase4 PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_compile_options(test_phase4 PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE)

add_test(NAME test_phase4 COMMAND test_phase4)
