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
