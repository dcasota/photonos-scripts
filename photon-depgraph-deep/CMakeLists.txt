cmake_minimum_required(VERSION 3.10)
project(photon-depgraph-deep C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -D_GNU_SOURCE -Wno-format-truncation")

find_package(PkgConfig REQUIRED)
pkg_check_modules(JSON_C REQUIRED json-c)

set(SOURCES
    src/main.c
    src/graph.c
    src/spec_parser.c
    src/gomod_analyzer.c
    src/gomod_to_package_map.c
    src/pyproject_analyzer.c
    src/api_version_extractor.c
    src/virtual_provides.c
    src/conflict_detector.c
    src/spec_patcher.c
    src/manifest_writer.c
    src/json_output.c
)

add_executable(photon-depgraph-deep ${SOURCES})
target_include_directories(photon-depgraph-deep PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${JSON_C_INCLUDE_DIRS}
)
target_link_libraries(photon-depgraph-deep ${JSON_C_LIBRARIES})

install(TARGETS photon-depgraph-deep DESTINATION bin)
