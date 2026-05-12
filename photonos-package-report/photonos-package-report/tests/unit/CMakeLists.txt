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

# ----- Phase 5 unit tests (urlhealth + Koji parsers) ------------------
add_executable(test_phase5
    test_phase5.c
    ${CMAKE_SOURCE_DIR}/src/strutil.c
    ${CMAKE_SOURCE_DIR}/src/urlhealth.c
    ${CMAKE_SOURCE_DIR}/src/koji.c
)
target_include_directories(test_phase5 PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CURL_INCLUDE_DIRS}
)
target_link_libraries(test_phase5 PRIVATE ${CURL_LIBRARIES})
target_compile_options(test_phase5 PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE ${CURL_CFLAGS_OTHER})

add_test(NAME test_phase5 COMMAND test_phase5)

# ----- Phase 6a unit tests (pr_state + prn writer + CheckURLHealth) ---
set_source_files_properties(${PR_GEN_HOOK_DISPATCH} PROPERTIES GENERATED TRUE)

add_executable(test_phase6
    test_phase6.c
    ${CMAKE_SOURCE_DIR}/src/state.c
    ${CMAKE_SOURCE_DIR}/src/strutil.c
    ${CMAKE_SOURCE_DIR}/src/source0_substitute.c
    ${CMAKE_SOURCE_DIR}/src/source0_lookup.c
    ${CMAKE_SOURCE_DIR}/src/urlhealth.c
    ${CMAKE_SOURCE_DIR}/src/prn_writer.c
    ${CMAKE_SOURCE_DIR}/src/check_urlhealth.c
    ${CMAKE_SOURCE_DIR}/src/hook_dispatch.c
    ${CMAKE_SOURCE_DIR}/src/task.c
    ${CMAKE_SOURCE_DIR}/src/clone.c
    ${CMAKE_SOURCE_DIR}/src/git_tags.c
    ${CMAKE_SOURCE_DIR}/src/git_with_timeout.c
    ${CMAKE_SOURCE_DIR}/src/latest_name.c
    ${CMAKE_SOURCE_DIR}/src/version.c
    ${CMAKE_SOURCE_DIR}/src/url_util.c
    ${CMAKE_SOURCE_DIR}/src/sha.c
    ${PR_GEN_HOOK_DISPATCH}
    ${PR_HOOK_SOURCES}
)
add_dependencies(test_phase6 pr-source0-lookup-data pr-hook-dispatch)
target_include_directories(test_phase6 PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${PR_GEN_DIR}
    ${PCRE2_INCLUDE_DIRS}
    ${CURL_INCLUDE_DIRS}
    ${OPENSSL_INCLUDE_DIRS}
)
target_link_libraries(test_phase6 PRIVATE pthread ${PCRE2_LIBRARIES} ${CURL_LIBRARIES} ${OPENSSL_LIBRARIES})
target_compile_options(test_phase6 PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE ${PCRE2_CFLAGS_OTHER} ${CURL_CFLAGS_OTHER})

add_test(NAME test_phase6 COMMAND test_phase6)

# ----- Phase 6b unit tests (Parse-Version + Compare-VersionStrings) --
add_executable(test_phase6b
    test_phase6b.c
    ${CMAKE_SOURCE_DIR}/src/version.c
)
target_include_directories(test_phase6b PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${PCRE2_INCLUDE_DIRS}
)
target_link_libraries(test_phase6b PRIVATE pthread ${PCRE2_LIBRARIES})
target_compile_options(test_phase6b PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE ${PCRE2_CFLAGS_OTHER})

add_test(NAME test_phase6b COMMAND test_phase6b)

# ----- Phase 6c unit tests (Get-LatestName + git_tags parser) --------
add_executable(test_phase6c
    test_phase6c.c
    ${CMAKE_SOURCE_DIR}/src/latest_name.c
    ${CMAKE_SOURCE_DIR}/src/git_tags.c
    ${CMAKE_SOURCE_DIR}/src/version.c
)
target_include_directories(test_phase6c PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${PCRE2_INCLUDE_DIRS}
)
target_link_libraries(test_phase6c PRIVATE pthread ${PCRE2_LIBRARIES})
target_compile_options(test_phase6c PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE ${PCRE2_CFLAGS_OTHER})

add_test(NAME test_phase6c COMMAND test_phase6c)

# ----- Phase 6d unit tests (local-clone manager + git tag enumeration)
add_executable(test_phase6d
    test_phase6d.c
    ${CMAKE_SOURCE_DIR}/src/clone.c
    ${CMAKE_SOURCE_DIR}/src/git_tags.c
    ${CMAKE_SOURCE_DIR}/src/git_with_timeout.c
)
target_include_directories(test_phase6d PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${PCRE2_INCLUDE_DIRS}
)
target_link_libraries(test_phase6d PRIVATE pthread ${PCRE2_LIBRARIES})
target_compile_options(test_phase6d PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE ${PCRE2_CFLAGS_OTHER})

add_test(NAME test_phase6d COMMAND test_phase6d)

# ----- Phase 6e unit tests (HeapSort + JDK picker + URL basename) ----
add_executable(test_phase6e
    test_phase6e.c
    ${CMAKE_SOURCE_DIR}/src/heapsort.c
    ${CMAKE_SOURCE_DIR}/src/jdk.c
    ${CMAKE_SOURCE_DIR}/src/url_util.c
)
target_include_directories(test_phase6e PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_compile_options(test_phase6e PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE)

add_test(NAME test_phase6e COMMAND test_phase6e)

# ----- Phase 6f unit tests (SHA helpers + diff_report) ----------------
add_executable(test_phase6f
    test_phase6f.c
    ${CMAKE_SOURCE_DIR}/src/sha.c
    ${CMAKE_SOURCE_DIR}/src/diff_report.c
    ${CMAKE_SOURCE_DIR}/src/version.c
    ${CMAKE_SOURCE_DIR}/src/task.c
)
target_include_directories(test_phase6f PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${PCRE2_INCLUDE_DIRS}
    ${CURL_INCLUDE_DIRS}
    ${OPENSSL_INCLUDE_DIRS}
)
target_link_libraries(test_phase6f PRIVATE pthread ${PCRE2_LIBRARIES} ${CURL_LIBRARIES} ${OPENSSL_LIBRARIES})
target_compile_options(test_phase6f PRIVATE -Wall -Wextra -O0 -g -D_GNU_SOURCE ${PCRE2_CFLAGS_OTHER} ${CURL_CFLAGS_OTHER} ${OPENSSL_CFLAGS_OTHER})

add_test(NAME test_phase6f COMMAND test_phase6f)
