CC      = gcc
CFLAGS  = -std=c99 -D_POSIX_C_SOURCE=200809L -D_GNU_SOURCE \
          -Wall -Wextra -Werror \
          -fstack-protector-strong -D_FORTIFY_SOURCE=2 \
          -fPIE -O2
LDFLAGS = -pie -Wl,-z,relro,-z,now
LIBS    = -lsqlite3 -lz -lm

SRC_DIR = src
SRCS    = $(SRC_DIR)/main.c \
          $(SRC_DIR)/security.c \
          $(SRC_DIR)/csv_parser.c \
          $(SRC_DIR)/db.c \
          $(SRC_DIR)/chart_xml.c \
          $(SRC_DIR)/docx_writer.c

OBJS    = $(SRCS:.c=.o)
TARGET  = photon-report-db

TEST_DIR    = test
TEST_SRCS   = $(TEST_DIR)/test_csv_parser.c \
              $(TEST_DIR)/test_db.c
TEST_COMMON = $(SRC_DIR)/security.o $(SRC_DIR)/csv_parser.o $(SRC_DIR)/db.o \
              $(SRC_DIR)/chart_xml.o $(SRC_DIR)/docx_writer.o

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

$(SRC_DIR)/%.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c -o $@ $<

$(TEST_DIR)/%.o: $(TEST_DIR)/%.c
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c -o $@ $<

test: $(TARGET) $(TEST_DIR)/test_csv_parser.o $(TEST_DIR)/test_db.o
	$(CC) $(LDFLAGS) -o $(TEST_DIR)/test_csv_parser $(TEST_DIR)/test_csv_parser.o $(TEST_COMMON) $(LIBS)
	$(CC) $(LDFLAGS) -o $(TEST_DIR)/test_db $(TEST_DIR)/test_db.o $(TEST_COMMON) $(LIBS)
	@echo "=== Running CSV Parser Tests ==="
	$(TEST_DIR)/test_csv_parser
	@echo "=== Running DB Tests ==="
	$(TEST_DIR)/test_db
	@echo "=== All tests passed ==="

clean:
	rm -f $(OBJS) $(TARGET)
	rm -f $(TEST_DIR)/*.o $(TEST_DIR)/test_csv_parser $(TEST_DIR)/test_db
	rm -f $(TEST_DIR)/test_*.db $(TEST_DIR)/test_output.docx
