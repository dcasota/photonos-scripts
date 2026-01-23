# PhotonOS-HABv4Emulation-ISOCreator Makefile

CC = gcc
CFLAGS = -Wall -O2 -g -Wno-format-truncation -Wno-stringop-truncation
TARGET = PhotonOS-HABv4Emulation-ISOCreator

# Sources
SRCS = PhotonOS-HABv4Emulation-ISOCreator.c rpm_secureboot_patcher.c
HDRS = rpm_secureboot_patcher.h

# Sub-projects
HAB_PRELOADER_DIR = hab/preloader
HAB_ISO_DIR = hab/iso

.PHONY: all clean install hab-preloader hab-iso

all: $(TARGET) hab-iso

$(TARGET): $(SRCS) $(HDRS)
	$(CC) $(CFLAGS) -o $@ $(SRCS)
	@echo "Built: $@ ($$(stat -c%s $@) bytes)"

hab-preloader:
	@if [ -f $(HAB_PRELOADER_DIR)/Makefile ]; then \
		$(MAKE) -C $(HAB_PRELOADER_DIR); \
	fi

hab-iso:
	@if [ -f $(HAB_ISO_DIR)/Makefile ]; then \
		$(MAKE) -C $(HAB_ISO_DIR); \
	fi

clean:
	rm -f $(TARGET)
	@if [ -f $(HAB_PRELOADER_DIR)/Makefile ]; then \
		$(MAKE) -C $(HAB_PRELOADER_DIR) clean; \
	fi
	@if [ -f $(HAB_ISO_DIR)/Makefile ]; then \
		$(MAKE) -C $(HAB_ISO_DIR) clean; \
	fi

install: $(TARGET)
	install -m 755 $(TARGET) /usr/local/bin/
	@echo "Installed to /usr/local/bin/$(TARGET)"

help:
	@echo "Targets:"
	@echo "  all           - Build main tool and sub-projects"
	@echo "  clean         - Remove build artifacts"
	@echo "  install       - Install to /usr/local/bin"
	@echo "  hab-preloader - Build HAB PreLoader (requires efitools)"
	@echo "  hab-iso       - Build hab_iso tool"
