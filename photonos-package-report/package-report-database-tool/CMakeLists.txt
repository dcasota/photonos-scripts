cmake_minimum_required(VERSION 3.10)
project(photon-report-db C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=2")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,relro,-z,now")

add_definitions(-D_POSIX_C_SOURCE=200809L -D_GNU_SOURCE)

find_package(PkgConfig QUIET)

# SQLite3
find_library(SQLITE3_LIB sqlite3 REQUIRED)
find_path(SQLITE3_INCLUDE sqlite3.h)

# zlib
find_package(ZLIB REQUIRED)

add_executable(photon-report-db
    src/main.c
    src/security.c
    src/csv_parser.c
    src/db.c
    src/chart_xml.c
    src/docx_writer.c
)

target_include_directories(photon-report-db PRIVATE src ${SQLITE3_INCLUDE} ${ZLIB_INCLUDE_DIRS})
target_link_libraries(photon-report-db ${SQLITE3_LIB} ${ZLIB_LIBRARIES} m)

# Position-independent executable
set_target_properties(photon-report-db PROPERTIES POSITION_INDEPENDENT_CODE ON)

# Tests
enable_testing()

add_executable(test_csv_parser test/test_csv_parser.c
    src/security.c src/csv_parser.c src/db.c src/chart_xml.c src/docx_writer.c)
target_include_directories(test_csv_parser PRIVATE src)
target_link_libraries(test_csv_parser ${SQLITE3_LIB} ${ZLIB_LIBRARIES} m)
add_test(NAME csv_parser COMMAND test_csv_parser)

add_executable(test_db test/test_db.c
    src/security.c src/csv_parser.c src/db.c src/chart_xml.c src/docx_writer.c)
target_include_directories(test_db PRIVATE src)
target_link_libraries(test_db ${SQLITE3_LIB} ${ZLIB_LIBRARIES} m)
add_test(NAME db COMMAND test_db)
