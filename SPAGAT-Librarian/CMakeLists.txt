cmake_minimum_required(VERSION 3.10)
project(spagat-librarian VERSION 0.2.0 LANGUAGES C CXX)

# Linux/Photon OS only
if(NOT UNIX)
    message(FATAL_ERROR "SPAGAT-Librarian only supports Linux/Photon OS")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_definitions(_POSIX_C_SOURCE=200809L _DEFAULT_SOURCE)

# Find required packages
find_package(PkgConfig REQUIRED)
pkg_check_modules(SQLITE3 REQUIRED sqlite3)
pkg_check_modules(NCURSES REQUIRED ncurses)

# Embedded model support (GGUF format for llama.cpp):
#   cmake -DEMBED_MODEL=path/to/model.gguf -DLLM_CTX_SIZE=4096 ..
# Supported models (set LLM_CTX_SIZE to match):
#   gemma2  = 1024   (bartowski/gemma-2-2b-it-GGUF)
#   llama   = 8192   (bartowski/Llama-3.2-1B-Instruct-GGUF)
#   bitnet  = 2048   (microsoft/bitnet-b1.58-2B-4T-gguf) — needs bitnet.cpp
#   qwen    = 4096   (bartowski/Qwen2.5-1.5B-Instruct-GGUF)
#   gemma3  = 8192   (bartowski/google_gemma-3-1b-it-GGUF)
set(EMBED_MODEL "" CACHE FILEPATH "Path to .gguf model file to embed into binary")
set(LLM_CTX_SIZE "2048" CACHE STRING "Default context size for the embedded model")

# Source files
set(SOURCES
    src/main.c
    src/db/db.c
    src/db/db_ext.c
    src/db/db_project.c
    src/db/db_template.c
    src/db/migrate.c
    src/cli/cli.c
    src/cli/cli_ext.c
    src/cli/cli_ai.c
    src/cli/cli_ai_cmds.c
    src/cli/cli_ai_subagent.c
    src/cli/cli_dispatch.c
    src/cli/input_classify.c
    src/cli/agent_input.c
    src/tui/tui.c
    src/tui/tui_board.c
    src/tui/tui_input.c
    src/tui/tui_dialogs.c
    src/tui/tui_dialogs_misc.c
    src/tui/tui_ext.c
    src/util/util.c
    src/util/journal.c
    src/ai/local.c
    src/ai/local_prompt.c
    src/ai/conversation.c
    src/ai/streaming.c
    src/ai/memory.c
    src/ai/tools.c
    src/ai/tools_builtin.c
    src/ai/tools_fs.c
    src/ai/tools_fs_read.c
    src/ai/tools_fs_write.c
    src/ai/tools_sysinfo.c
    src/ai/autonomy.c
    src/ai/execpolicy.c
    src/ai/sanitize.c
    src/ai/prompt_builder.c
    src/ai/compaction.c
    src/ai/linux_sandbox.c
    src/ai/git_tools.c
    src/ai/sysaware.c
    src/ai/embedded_model.c
    src/agent/workspace.c
    src/agent/onboard.c
    src/agent/config_io.c
    src/agent/scheduler.c
    src/agent/sandbox.c
    src/agent/heartbeat.c
    src/agent/subagent.c
    src/skill/loader.c
    src/skill/executor.c
    src/ai/llama_bridge.cpp
)

# Create executable
add_executable(spagat-librarian ${SOURCES})

# Embed GGUF model via objcopy if EMBED_MODEL is set
if(EMBED_MODEL)
    if(NOT EXISTS "${EMBED_MODEL}")
        message(FATAL_ERROR "Model file not found: ${EMBED_MODEL}")
    endif()

    set(MODEL_OBJ "${CMAKE_BINARY_DIR}/model_data.o")

    add_custom_command(
        OUTPUT "${MODEL_OBJ}"
        COMMAND ${CMAKE_COMMAND} -E copy "${EMBED_MODEL}" "${CMAKE_BINARY_DIR}/model.gguf"
        COMMAND objcopy -I binary -O elf64-x86-64 -B i386:x86-64
            --rename-section .data=.rodata,alloc,load,readonly,data,contents
            model.gguf model_data.o
        COMMAND objcopy --add-section .note.GNU-stack=/dev/null
            --set-section-flags .note.GNU-stack=noload,readonly
            model_data.o
        COMMAND ${CMAKE_COMMAND} -E remove "${CMAKE_BINARY_DIR}/model.gguf"
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        DEPENDS "${EMBED_MODEL}"
        COMMENT "Embedding GGUF model: ${EMBED_MODEL}"
    )

    target_sources(spagat-librarian PRIVATE "${MODEL_OBJ}")
    set_source_files_properties("${MODEL_OBJ}" PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
    target_link_libraries(spagat-librarian PRIVATE "${MODEL_OBJ}")
    target_compile_definitions(spagat-librarian PRIVATE
        SPAGAT_EMBED_MODEL
        SPAGAT_DEFAULT_N_CTX=${LLM_CTX_SIZE}
    )

    message(STATUS "Embedded GGUF model: ${EMBED_MODEL} (ctx=${LLM_CTX_SIZE})")
else()
    message(STATUS "No embedded model (use -DEMBED_MODEL=path/to/model.gguf -DLLM_CTX_SIZE=N to embed)")
endif()

# Include directories
target_include_directories(spagat-librarian PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/_deps/llama.cpp/include
    ${CMAKE_SOURCE_DIR}/_deps/llama.cpp/ggml/include
    ${SQLITE3_INCLUDE_DIRS}
    ${NCURSES_INCLUDE_DIRS}
)

# Link libraries
target_link_libraries(spagat-librarian PRIVATE
    ${SQLITE3_LIBRARIES}
    ${NCURSES_LIBRARIES}
    llama
)

# Install
install(TARGETS spagat-librarian RUNTIME DESTINATION bin)

# CPack configuration
set(CPACK_PACKAGE_NAME "spagat-librarian")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Kanban Task Manager for Photon OS")
include(CPack)
