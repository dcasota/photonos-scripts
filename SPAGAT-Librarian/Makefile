# SPAGAT-Librarian Makefile (Photon OS / Linux only)
#
# Quick start (interactive — does everything):
#   make setup
#
# Manual steps (if you prefer):
#   make deps          # install OS packages
#   make llama         # build & install llama.cpp runtime
#   make model         # download default LLM GGUF from HuggingFace
#   make MODEL=models/<model>.gguf
#
# Choose an LLM (default: gemma2):
#   make model LLM=gemma2      # Google Gemma-2 2B IT       (1.7 GB, ctx 1024)
#   make model LLM=llama       # Meta Llama-3.2 1B Instruct (0.8 GB, ctx 8192)
#   make model LLM=bitnet      # Microsoft BitNet b1.58 2B  (1.2 GB, ctx 2048) *
#   make model LLM=qwen        # Alibaba Qwen2.5 1.5B       (1.0 GB, ctx 4096)
#   make model LLM=gemma3      # Google Gemma-3 1B IT       (0.8 GB, ctx 8192)
#
#   * BitNet requires bitnet.cpp (not standard llama.cpp). See: make bitnet
#
# Build with embedded model:
#   make model LLM=llama
#   make MODEL=models/Llama-3.2-1B-Instruct-Q4_K_M.gguf LLM=llama
#
# Without embedded model (uses ~/.spagat/config.json model_path):
#   make

CC = gcc
CXX = g++
CFLAGS = -Wall -Wextra -std=c11 -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE -I./include -I./src
CXXFLAGS = -Wall -Wextra -std=c++17 -I./include -I./src -I/usr/include -I./_deps/llama.cpp/include -I./_deps/llama.cpp/ggml/include -I./_deps/bitnet/3rdparty/llama.cpp/include -I./_deps/bitnet/3rdparty/llama.cpp/ggml/include
ifdef BITNET_BUILD
  CXXFLAGS += -DLLAMA_OLD_API=1
endif
LDFLAGS = -lsqlite3 -lncurses -lllama -lstdc++
ifdef BITNET_BUILD
  LDFLAGS += -lggml
endif

# Embedded model support (GGUF format for llama.cpp):
#   make MODEL=path/to/gemma-2-2b-it-Q4_K_M.gguf
# This embeds the model into the binary via objcopy + memfd_create.
# Without MODEL=, the binary expects an external model file in config.
MODEL ?=

# ---- LLM selection --------------------------------------------------------
# Set LLM= to choose which model to download / embed.
# Each defines: GGUF_REPO, GGUF_FILE, LLM_CTX_SIZE (default context window).
LLM ?= gemma2
MODELS_DIR = models

ifeq ($(LLM),gemma2)
  # Google Gemma-2 2B IT — compact, good general quality
  GGUF_REPO      = bartowski/gemma-2-2b-it-GGUF
  GGUF_FILE      = gemma-2-2b-it-Q4_K_M.gguf
  LLM_CTX_SIZE   = 1024
  LLM_LABEL      = Gemma-2 2B IT (Q4_K_M)
else ifeq ($(LLM),llama)
  # Meta Llama-3.2 1B Instruct — fast, large context
  GGUF_REPO      = bartowski/Llama-3.2-1B-Instruct-GGUF
  GGUF_FILE      = Llama-3.2-1B-Instruct-Q4_K_M.gguf
  LLM_CTX_SIZE   = 8192
  LLM_LABEL      = Llama-3.2 1B Instruct (Q4_K_M)
else ifeq ($(LLM),bitnet)
  # Microsoft BitNet b1.58 2B 4T — native 1-bit, requires bitnet.cpp
  GGUF_REPO      = microsoft/bitnet-b1.58-2B-4T-gguf
  GGUF_FILE      = ggml-model-i2_s.gguf
  LLM_CTX_SIZE   = 2048
  LLM_LABEL      = BitNet b1.58 2B 4T (i2_s) [requires bitnet.cpp]
else ifeq ($(LLM),qwen)
  # Alibaba Qwen2.5 1.5B Instruct — multilingual, strong reasoning
  GGUF_REPO      = bartowski/Qwen2.5-1.5B-Instruct-GGUF
  GGUF_FILE      = Qwen2.5-1.5B-Instruct-Q4_K_M.gguf
  LLM_CTX_SIZE   = 4096
  LLM_LABEL      = Qwen2.5 1.5B Instruct (Q4_K_M)
else ifeq ($(LLM),gemma3)
  # Google Gemma-3 1B IT — newest, large context
  GGUF_REPO      = bartowski/google_gemma-3-1b-it-GGUF
  GGUF_FILE      = google_gemma-3-1b-it-Q4_K_M.gguf
  LLM_CTX_SIZE   = 8192
  LLM_LABEL      = Gemma-3 1B IT (Q4_K_M)
else
  $(error Unknown LLM='$(LLM)'. Valid: gemma2 llama bitnet qwen gemma3)
endif

GGUF_URL   = https://huggingface.co/$(GGUF_REPO)/resolve/main/$(GGUF_FILE)
MODEL_PATH = $(MODELS_DIR)/$(GGUF_FILE)

# llama.cpp build settings
LLAMA_REPO      = https://github.com/ggml-org/llama.cpp.git
LLAMA_DIR       = _deps/llama.cpp
LLAMA_BUILD     = $(LLAMA_DIR)/build

# Source files
SRCDIR = src
SOURCES = $(SRCDIR)/main.c \
          $(SRCDIR)/db/db.c \
          $(SRCDIR)/db/db_ext.c \
          $(SRCDIR)/db/db_project.c \
          $(SRCDIR)/db/db_template.c \
          $(SRCDIR)/db/migrate.c \
          $(SRCDIR)/cli/cli.c \
          $(SRCDIR)/cli/cli_ext.c \
          $(SRCDIR)/cli/cli_ai.c \
          $(SRCDIR)/cli/cli_ai_cmds.c \
          $(SRCDIR)/cli/cli_ai_subagent.c \
          $(SRCDIR)/cli/cli_dispatch.c \
          $(SRCDIR)/cli/input_classify.c \
          $(SRCDIR)/cli/agent_input.c \
          $(SRCDIR)/tui/tui.c \
          $(SRCDIR)/tui/tui_board.c \
          $(SRCDIR)/tui/tui_input.c \
          $(SRCDIR)/tui/tui_dialogs.c \
          $(SRCDIR)/tui/tui_dialogs_misc.c \
          $(SRCDIR)/tui/tui_ext.c \
          $(SRCDIR)/util/util.c \
          $(SRCDIR)/util/journal.c \
          $(SRCDIR)/ai/local.c \
          $(SRCDIR)/ai/local_prompt.c \
          $(SRCDIR)/ai/conversation.c \
          $(SRCDIR)/ai/streaming.c \
          $(SRCDIR)/ai/memory.c \
          $(SRCDIR)/ai/tools.c \
          $(SRCDIR)/ai/tools_builtin.c \
          $(SRCDIR)/ai/tools_fs.c \
          $(SRCDIR)/ai/tools_fs_read.c \
          $(SRCDIR)/ai/tools_fs_write.c \
          $(SRCDIR)/ai/tools_sysinfo.c \
          $(SRCDIR)/ai/autonomy.c \
          $(SRCDIR)/ai/execpolicy.c \
          $(SRCDIR)/ai/sanitize.c \
          $(SRCDIR)/ai/prompt_builder.c \
          $(SRCDIR)/ai/compaction.c \
          $(SRCDIR)/ai/linux_sandbox.c \
          $(SRCDIR)/ai/git_tools.c \
          $(SRCDIR)/ai/sysaware.c \
          $(SRCDIR)/ai/embedded_model.c \
          $(SRCDIR)/agent/workspace.c \
          $(SRCDIR)/agent/onboard.c \
          $(SRCDIR)/agent/config_io.c \
          $(SRCDIR)/agent/scheduler.c \
          $(SRCDIR)/agent/sandbox.c \
          $(SRCDIR)/agent/heartbeat.c \
          $(SRCDIR)/agent/subagent.c \
          $(SRCDIR)/skill/loader.c \
          $(SRCDIR)/skill/executor.c

# C++ bridge source (compiled with g++ against llama.h)
CXX_SOURCES = $(SRCDIR)/ai/llama_bridge.cpp

# Object files
OBJDIR = obj
OBJECTS = $(SOURCES:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
OBJECTS += $(CXX_SOURCES:$(SRCDIR)/%.cpp=$(OBJDIR)/%.o)

# Embedded model object (only when MODEL= is set)
ifneq ($(MODEL),)
CFLAGS += -DSPAGAT_EMBED_MODEL -DSPAGAT_DEFAULT_N_CTX=$(LLM_CTX_SIZE)
CXXFLAGS += -DSPAGAT_EMBED_MODEL -DSPAGAT_DEFAULT_N_CTX=$(LLM_CTX_SIZE)
MODEL_OBJ = $(OBJDIR)/ai/model_data.o
OBJECTS += $(MODEL_OBJ)
endif

# Output
TARGET = spagat-librarian

# Debug build
DEBUG_CFLAGS = -g -O0 -DDEBUG

# Release build
RELEASE_CFLAGS = -O2 -DNDEBUG

.PHONY: all clean debug release install help deps llama bitnet model models model-all setup FORCE

all: release

debug: CFLAGS += $(DEBUG_CFLAGS)
debug: CXXFLAGS += $(DEBUG_CFLAGS)
debug: $(TARGET)

release: CFLAGS += $(RELEASE_CFLAGS)
release: CXXFLAGS += $(RELEASE_CFLAGS)
release: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(OBJECTS) -o $@ $(LDFLAGS)

$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR)/%.o: $(SRCDIR)/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Embed GGUF model file into an ELF object via objcopy.
# Produces symbols: _binary_model_gguf_start, _binary_model_gguf_end
ifneq ($(MODEL),)
$(MODEL_OBJ): $(MODEL) FORCE
	@mkdir -p $(dir $@)
	@echo "Embedding model: $(MODEL) ($(shell du -sh $(MODEL) | cut -f1))"
	cp $(MODEL) $(OBJDIR)/ai/model.gguf
	cd $(OBJDIR)/ai && objcopy -I binary -O elf64-x86-64 \
		-B i386:x86-64 \
		--rename-section .data=.rodata,alloc,load,readonly,data,contents \
		model.gguf model_data.o
	@# Add non-executable .note.GNU-stack section via objcopy
	objcopy --add-section .note.GNU-stack=/dev/null \
		--set-section-flags .note.GNU-stack=noload,readonly \
		$(OBJDIR)/ai/model_data.o
	@rm -f $(OBJDIR)/ai/model.gguf
	@echo "Model embedded successfully."
FORCE:
endif

clean:
	rm -rf $(OBJDIR) $(TARGET)

install: $(TARGET)
	install -d $(DESTDIR)/usr/bin
	install -m 755 $(TARGET) $(DESTDIR)/usr/bin/

# Dependencies
$(OBJDIR)/main.o: $(SRCDIR)/main.c include/spagat.h
$(OBJDIR)/db/db.o: $(SRCDIR)/db/db.c $(SRCDIR)/db/db.h $(SRCDIR)/db/migrate.h include/spagat.h
$(OBJDIR)/db/migrate.o: $(SRCDIR)/db/migrate.c $(SRCDIR)/db/migrate.h $(SRCDIR)/db/db.h
$(OBJDIR)/cli/cli.o: $(SRCDIR)/cli/cli.c $(SRCDIR)/cli/cli.h include/spagat.h
$(OBJDIR)/tui/tui.o: $(SRCDIR)/tui/tui.c $(SRCDIR)/tui/tui.h $(SRCDIR)/tui/tui_common.h include/spagat.h
$(OBJDIR)/tui/tui_board.o: $(SRCDIR)/tui/tui_board.c $(SRCDIR)/tui/tui_common.h include/spagat.h
$(OBJDIR)/tui/tui_input.o: $(SRCDIR)/tui/tui_input.c $(SRCDIR)/tui/tui_common.h include/spagat.h
$(OBJDIR)/tui/tui_dialogs.o: $(SRCDIR)/tui/tui_dialogs.c $(SRCDIR)/tui/tui_common.h include/spagat.h
$(OBJDIR)/tui/tui_dialogs_misc.o: $(SRCDIR)/tui/tui_dialogs_misc.c $(SRCDIR)/tui/tui_common.h include/spagat.h
$(OBJDIR)/util/util.o: $(SRCDIR)/util/util.c $(SRCDIR)/util/util.h

# =============================================================================
# Prerequisites
# =============================================================================

# Install OS-level build dependencies (Photon OS)
# Note: On Photon OS, g++ is included in gcc; libstdc++ provides the C++ runtime.
deps:
	@echo "=== Installing build dependencies (requires root) ==="
	tdnf install -y gcc libstdc++ make cmake sqlite-devel ncurses-devel binutils git curl

# Build and install llama.cpp shared library
# Note: BUILD_SHARED_LIBS=ON places .so files in build/bin/, not build/src/
llama: $(LLAMA_BUILD)/bin/libllama.so
	@echo "=== Installing libllama.so ==="
	install -m 755 $(LLAMA_BUILD)/bin/libllama.so /usr/lib/
	install -m 755 $(LLAMA_BUILD)/bin/libggml.so /usr/lib/ 2>/dev/null || true
	install -m 755 $(LLAMA_BUILD)/bin/libggml-base.so /usr/lib/ 2>/dev/null || true
	install -m 755 $(LLAMA_BUILD)/bin/libggml-cpu.so /usr/lib/ 2>/dev/null || true
	install -d /usr/include
	install -m 644 $(LLAMA_DIR)/include/llama.h /usr/include/ 2>/dev/null || true
	install -m 644 $(LLAMA_DIR)/ggml/include/ggml.h /usr/include/ 2>/dev/null || true
	install -m 644 $(LLAMA_DIR)/ggml/include/ggml-alloc.h /usr/include/ 2>/dev/null || true
	install -m 644 $(LLAMA_DIR)/ggml/include/ggml-backend.h /usr/include/ 2>/dev/null || true
	ldconfig
	@echo "llama.cpp installed successfully."

$(LLAMA_BUILD)/bin/libllama.so:
	@echo "=== Building llama.cpp from source ==="
	@if [ ! -d "$(LLAMA_DIR)" ]; then \
		git clone --depth 1 $(LLAMA_REPO) $(LLAMA_DIR); \
	fi
	cmake -S $(LLAMA_DIR) -B $(LLAMA_BUILD) \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DLLAMA_BUILD_TESTS=OFF \
		-DLLAMA_BUILD_EXAMPLES=OFF \
		-DLLAMA_BUILD_SERVER=OFF
	cmake --build $(LLAMA_BUILD) --config Release -j$$(nproc)

# Download GGUF model from HuggingFace (respects LLM= selection)
model: $(MODEL_PATH)

$(MODEL_PATH):
	@echo "=== Downloading $(LLM_LABEL) from HuggingFace ==="
	@echo "  Repo:     $(GGUF_REPO)"
	@echo "  File:     $(GGUF_FILE)"
	@echo "  Ctx size: $(LLM_CTX_SIZE)"
ifeq ($(LLM),bitnet)
	@echo ""
	@echo "  Note: BitNet i2_s requires 'make bitnet' (builds bitnet.cpp libllama.so)"
	@echo ""
endif
	@mkdir -p $(MODELS_DIR)
	curl -L --progress-bar -o $(MODEL_PATH).tmp "$(GGUF_URL)"
	mv $(MODEL_PATH).tmp $(MODEL_PATH)
	@echo "Model downloaded: $(MODEL_PATH) ($$(du -sh $(MODEL_PATH) | cut -f1))"

# List available LLMs
models:
	@echo "Available LLMs (set with LLM=<name>):"
	@echo ""
	@echo "  gemma2   Gemma-2 2B IT         1.7 GB  ctx=1024   bartowski/gemma-2-2b-it-GGUF"
	@echo "  llama    Llama-3.2 1B Instruct  0.8 GB  ctx=8192   bartowski/Llama-3.2-1B-Instruct-GGUF"
	@echo "  bitnet   BitNet b1.58 2B 4T     1.2 GB  ctx=2048   microsoft/bitnet-b1.58-2B-4T-gguf *"
	@echo "  qwen     Qwen2.5 1.5B Instruct  1.0 GB  ctx=4096   bartowski/Qwen2.5-1.5B-Instruct-GGUF"
	@echo "  gemma3   Gemma-3 1B IT          0.8 GB  ctx=8192   bartowski/google_gemma-3-1b-it-GGUF"
	@echo ""
	@echo "  * BitNet requires bitnet.cpp (not standard llama.cpp)"
	@echo ""
	@echo "Current selection: LLM=$(LLM) -> $(LLM_LABEL)"
	@echo ""
	@echo "Download:  make model LLM=<name>"
	@echo "Embed:     make MODEL=models/<file>.gguf LLM=<name>"

# Interactive all-in-one: choose LLM, install deps, build llama.cpp,
# download model, build binary with embedded GGUF.
# BitNet also builds bitnet.cpp and auto-embeds Gemma-3 1B for the agent.
setup:
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║           SPAGAT-Librarian — Interactive Setup              ║"
	@echo "╠══════════════════════════════════════════════════════════════╣"
	@echo "║  #  LLM                        Size    Context  Speed      ║"
	@echo "║  1  Gemma-2 2B IT (Q4_K_M)     1.7 GB  1024    balanced   ║"
	@echo "║  2  Llama-3.2 1B (Q4_K_M)      0.8 GB  8192    fast       ║"
	@echo "║  3  Qwen2.5 1.5B (Q4_K_M)      1.0 GB  4096    fast       ║"
	@echo "║  4  Gemma-3 1B IT (Q4_K_M)     0.8 GB  8192    fast       ║"
	@echo "╠══════════════════════════════════════════════════════════════╣"
	@echo "║  5  BitNet b1.58 2B (i2_s)     1.2 GB  2048    1-bit      ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo "  Note: BitNet requires clang, clang-devel, and python."
	@echo ""
	@read -p "Select LLM [1-5] (default: 1): " choice; \
	case "$${choice:-1}" in \
		1) llm=gemma2; file=gemma-2-2b-it-Q4_K_M.gguf ;; \
		2) llm=llama;  file=Llama-3.2-1B-Instruct-Q4_K_M.gguf ;; \
		3) llm=qwen;   file=Qwen2.5-1.5B-Instruct-Q4_K_M.gguf ;; \
		4) llm=gemma3;  file=google_gemma-3-1b-it-Q4_K_M.gguf ;; \
		5) llm=bitnet;  file=ggml-model-i2_s.gguf ;; \
		*) echo "Invalid choice."; exit 1 ;; \
	esac; \
	echo ""; \
	echo "=== Selected: $$llm ==="; \
	echo ""; \
	$(MAKE) deps; \
	if [ "$$llm" = "bitnet" ]; then \
		$(MAKE) bitnet; \
	else \
		$(MAKE) llama; \
	fi; \
	$(MAKE) model LLM=$$llm; \
	if [ "$$llm" = "bitnet" ]; then \
		$(MAKE) MODEL=models/$$file LLM=$$llm BITNET_BUILD=1; \
	else \
		$(MAKE) MODEL=models/$$file LLM=$$llm; \
	fi; \
	echo ""; \
	echo "=== Setup complete ==="; \
	echo "Binary: ./spagat-librarian (with embedded $$llm model)"; \
	echo "Run:    ./spagat-librarian agent"

# Download all models at once
model-all:
	$(MAKE) model LLM=gemma2
	$(MAKE) model LLM=llama
	$(MAKE) model LLM=bitnet
	$(MAKE) model LLM=qwen
	$(MAKE) model LLM=gemma3
	@echo "All models downloaded to $(MODELS_DIR)/"

# --------------------------------------------------------------------------
# BitNet support (separate from llama.cpp)
# --------------------------------------------------------------------------
BITNET_REPO = https://github.com/microsoft/BitNet.git
BITNET_DIR  = _deps/bitnet

BITNET_LLAMA_LIB = $(BITNET_DIR)/build/3rdparty/llama.cpp/src/libllama.so
BITNET_GGML_LIB  = $(BITNET_DIR)/build/3rdparty/llama.cpp/ggml/src/libggml.so
BITNET_LLAMA_INC = $(BITNET_DIR)/3rdparty/llama.cpp/include
BITNET_GGML_INC  = $(BITNET_DIR)/3rdparty/llama.cpp/ggml/include

bitnet: $(BITNET_LLAMA_LIB)
	@echo "=== Installing BitNet libllama.so (replaces standard llama.cpp) ==="
	install -m 755 $(BITNET_LLAMA_LIB) /usr/lib/
	install -m 755 $(BITNET_GGML_LIB) /usr/lib/ 2>/dev/null || true
	install -d /usr/include
	install -m 644 $(BITNET_LLAMA_INC)/llama.h /usr/include/ 2>/dev/null || true
	install -m 644 $(BITNET_GGML_INC)/ggml.h /usr/include/ 2>/dev/null || true
	install -m 644 $(BITNET_GGML_INC)/ggml-alloc.h /usr/include/ 2>/dev/null || true
	install -m 644 $(BITNET_GGML_INC)/ggml-backend.h /usr/include/ 2>/dev/null || true
	ldconfig
	@echo "=== bitnet.cpp installed (i2_s + standard GGUF support) ==="

# BitNet requires:
#   1. llama.cpp submodule (for ggml)
#   2. Python codegen to generate bitnet-lut-kernels.h (unavoidable)
#   3. clang/clang++ compiler (gcc will NOT work)
# Built as shared library so spagat-librarian can link against it directly.
# This libllama.so is a superset: supports i2_s (BitNet) AND standard quants.
$(BITNET_LLAMA_LIB):
	@echo "=== Building bitnet.cpp from source (shared library) ==="
	@command -v clang >/dev/null 2>&1 || { echo "ERROR: clang required. Run: tdnf install clang clang-devel"; exit 1; }
	@command -v python >/dev/null 2>&1 || { echo "ERROR: python required for BitNet kernel codegen."; exit 1; }
	@echo | clang -xc -include stddef.h - -E -o /dev/null 2>/dev/null || \
		{ echo "ERROR: clang resource headers missing (stddef.h). Run: tdnf install clang-devel"; exit 1; }
	@if [ ! -d "$(BITNET_DIR)" ]; then \
		git clone --depth 1 $(BITNET_REPO) $(BITNET_DIR); \
	fi
	@if [ ! -f "$(BITNET_DIR)/3rdparty/llama.cpp/CMakeLists.txt" ]; then \
		cd $(BITNET_DIR) && git submodule update --init --depth 1 3rdparty/llama.cpp; \
	fi
	cd $(BITNET_DIR) && pip install 3rdparty/llama.cpp/gguf-py 2>/dev/null || true
	@echo "--- Patching BitNet const-correctness bug (ggml-bitnet-mad.cpp:811) ---"
	sed -i 's/int8_t \* y_col = y + col \* by/const int8_t * y_col = y + col * by/' \
		$(BITNET_DIR)/src/ggml-bitnet-mad.cpp
	@echo "--- Generating BitNet LUT kernels (x86_64 i2_s) ---"
	cd $(BITNET_DIR) && python utils/codegen_tl2.py \
		--model bitnet_b1_58-3B \
		--BM 160,320,320 --BK 96,96,96 --bm 32,32,32
	@echo "--- Compiling with clang (shared library) ---"
	cd $(BITNET_DIR) && cmake -B build \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DBITNET_X86_TL2=OFF \
		-DGGML_OPENMP=OFF \
		-DGGML_CCACHE=OFF \
		-DCMAKE_C_COMPILER=clang \
		-DCMAKE_CXX_COMPILER=clang++ \
		-DCMAKE_C_FLAGS="-w" \
		-DCMAKE_CXX_FLAGS="-w"
	cd $(BITNET_DIR) && cmake --build build --config Release -j$$(nproc)

# Clean everything including downloaded deps and models
distclean: clean
	rm -rf _deps $(MODELS_DIR)

help:
	@echo "SPAGAT-Librarian Build System (Photon OS / Linux)"
	@echo ""
	@echo "Build targets:"
	@echo "  all                     - Build release version (default)"
	@echo "  debug                   - Build debug version"
	@echo "  release                 - Build optimized version"
	@echo "  clean                   - Remove build artifacts"
	@echo "  distclean               - Remove build artifacts + downloaded deps/models"
	@echo "  install                 - Install to system"
	@echo ""
	@echo "Prerequisite targets:"
	@echo "  deps                    - Install OS packages (gcc, cmake, sqlite, ncurses, git, curl)"
	@echo "  llama                   - Clone, build & install llama.cpp (libllama.so)"
	@echo "  bitnet                  - Clone & build bitnet.cpp (for BitNet models only)"
	@echo "  model LLM=<name>        - Download GGUF model from HuggingFace"
	@echo "  model-all               - Download all 5 models"
	@echo "  models                  - List available LLMs"
	@echo "  setup                   - Interactive: choose LLM, install deps, build everything"
	@echo ""
	@echo "Available LLMs (LLM=<name>):"
	@echo "  gemma2   Google Gemma-2 2B IT        ctx=1024  (default)"
	@echo "  llama    Meta Llama-3.2 1B Instruct  ctx=8192"
	@echo "  bitnet   MS BitNet b1.58 2B 4T       ctx=2048  (needs clang+python)"
	@echo "  qwen     Alibaba Qwen2.5 1.5B        ctx=4096"
	@echo "  gemma3   Google Gemma-3 1B IT        ctx=8192"
	@echo ""
	@echo "Embedded model build:"
	@echo "  make model LLM=llama"
	@echo "  make MODEL=$(MODELS_DIR)/Llama-3.2-1B-Instruct-Q4_K_M.gguf LLM=llama"
	@echo ""
	@echo "Quick start:"
	@echo "  make setup              - Install all prerequisites + download default model"
	@echo "  make MODEL=$(MODEL_PATH) LLM=$(LLM)"
	@echo "                          - Build with embedded $(LLM_LABEL)"
