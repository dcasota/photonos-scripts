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
