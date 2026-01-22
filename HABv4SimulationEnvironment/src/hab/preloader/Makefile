# HAB PreLoader Makefile
#
# Builds the HAB PreLoader using the complete efitools library
# from /root/src/kernel.org/efitools

ARCH		= x86_64
EFITOOLS_DIR	= /root/src/kernel.org/efitools

# GNU-EFI paths
GNUEFI_INC	= /usr/include/efi
GNUEFI_INC_ARCH	= $(GNUEFI_INC)/$(ARCH)
GNUEFI_LIB	= /usr/lib64
EFI_CRT		= $(GNUEFI_LIB)/crt0-efi-$(ARCH).o
EFI_LDS		= $(GNUEFI_LIB)/elf_$(ARCH)_efi.lds

# Compiler and tools
CC		= gcc
LD		= ld
OBJCOPY		= objcopy

# Include paths
INCLUDES	= -I. \
		  -I$(EFITOOLS_DIR)/include \
		  -I$(GNUEFI_INC) \
		  -I$(GNUEFI_INC_ARCH) \
		  -I$(GNUEFI_INC)/protocol

# Compiler flags (matching efitools exactly)
CFLAGS		= $(INCLUDES) \
		  -O2 -fpic -Wall \
		  -fshort-wchar \
		  -fno-strict-aliasing \
		  -fno-merge-constants \
		  -fno-stack-protector \
		  -ffreestanding \
		  -fno-stack-check \
		  -DGNU_EFI_USE_MS_ABI \
		  -mno-red-zone \
		  -DCONFIG_$(ARCH)

# Linker flags
LDFLAGS		= -nostdlib -znocombreloc \
		  -T $(EFI_LDS) \
		  -shared -Bsymbolic \
		  -L$(GNUEFI_LIB)

# Libraries
LIBS		= -lefi -lgnuefi

# efitools library (must be built first)
EFITOOLS_LIB	= $(EFITOOLS_DIR)/lib/lib-efi.a

# Output
TARGET		= HabPreLoader.efi
TARGET_SBAT	= HabPreLoader-sbat.efi

# SBAT data
SBAT_CSV	= sbat.csv

.PHONY: all clean install efitools-lib

all: $(TARGET_SBAT)

# Build efitools library if needed
efitools-lib:
	@echo "Building efitools library..."
	$(MAKE) -C $(EFITOOLS_DIR) lib/lib-efi.a ARCH=$(ARCH)

# Ensure efitools library exists
$(EFITOOLS_LIB): efitools-lib

# Compile HAB PreLoader
HabPreLoader.o: HabPreLoader.c hashlist.h
	$(CC) $(CFLAGS) -c -o $@ $<

# Link with efitools library
HabPreLoader.so: HabPreLoader.o $(EFITOOLS_LIB)
	$(LD) $(LDFLAGS) $(EFI_CRT) $< $(EFITOOLS_LIB) -o $@ $(LIBS)

# Convert to EFI PE format
$(TARGET): HabPreLoader.so
	$(OBJCOPY) -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
		   -j .rel -j .rela -j .reloc \
		   --target=efi-app-$(ARCH) $< $@
	@echo "Built: $@ ($$(stat -c%s $@) bytes)"

# Add SBAT section
$(TARGET_SBAT): $(TARGET) $(SBAT_CSV)
	$(OBJCOPY) --add-section .sbat=$(SBAT_CSV) \
		   --set-section-flags .sbat=alloc,data,readonly,contents \
		   $< $@
	@echo "Built with SBAT: $@ ($$(stat -c%s $@) bytes)"

# Create SBAT data if missing
$(SBAT_CSV):
	@echo "sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md" > $@

clean:
	rm -f *.o *.so *.efi $(SBAT_CSV)

# Install to hab_keys directory
install: $(TARGET_SBAT)
	@mkdir -p /root/hab_keys
	cp $(TARGET_SBAT) /root/hab_keys/hab-preloader.efi
	@echo "Installed to /root/hab_keys/hab-preloader.efi"

# Sign with MOK (requires MOK.key and MOK.crt)
sign: $(TARGET_SBAT)
	@if [ -f /root/hab_keys/MOK.key ] && [ -f /root/hab_keys/MOK.crt ]; then \
		sbsign --key /root/hab_keys/MOK.key \
		       --cert /root/hab_keys/MOK.crt \
		       --output /root/hab_keys/hab-preloader-signed.efi \
		       $(TARGET_SBAT) 2>&1; \
		echo "Signed: /root/hab_keys/hab-preloader-signed.efi"; \
	else \
		echo "Error: MOK.key and MOK.crt required in /root/hab_keys/"; \
		exit 1; \
	fi

# Show build info
info:
	@echo "HAB PreLoader Build Configuration"
	@echo "================================="
	@echo "Architecture: $(ARCH)"
	@echo "efitools:     $(EFITOOLS_DIR)"
	@echo "GNU-EFI:      $(GNUEFI_INC)"
	@echo "Output:       $(TARGET_SBAT)"
