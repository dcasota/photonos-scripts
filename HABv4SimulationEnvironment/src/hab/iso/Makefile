# HAB ISO Builder Makefile

CC = gcc
CFLAGS = -Wall -O2 -g -Wno-format-truncation -Wno-stringop-truncation
TARGET = hab_iso

all: $(TARGET)

$(TARGET): hab_iso.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/

.PHONY: all clean install
