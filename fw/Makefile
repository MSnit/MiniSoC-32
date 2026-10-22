# =============================================================================
#  MiniSoC-32 Firmware Makefile
# =============================================================================
CROSS   ?= riscv64-unknown-elf
CC       = $(CROSS)-gcc
AS       = $(CROSS)-as
OBJCOPY  = $(CROSS)-objcopy
OBJDUMP  = $(CROSS)-objdump

ARCH     = -march=rv32i_zicsr -mabi=ilp32
CFLAGS   = $(ARCH) -nostdlib -O2 -g -Wall -Wextra -Iinclude
LDFLAGS  = $(ARCH) -nostdlib -T link.ld -Wl,-Map=build/minisoc.map

BUILD    = build
SRCS     = src/startup.S src/main.c
OBJS     = $(BUILD)/startup.o $(BUILD)/main.o
ELF      = $(BUILD)/minisoc.elf
HEX      = $(BUILD)/minisoc.hex
BIN      = $(BUILD)/minisoc.bin
DUMP     = $(BUILD)/minisoc.dump

.PHONY: all clean dump

all: $(HEX)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/startup.o: src/startup.S | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/main.o: src/main.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(ELF): $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) -o $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(HEX): $(BIN)
	python3 bin2hex.py $< $@ 1024
	@echo "Firmware hex: $@"

dump: $(ELF)
	$(OBJDUMP) -d -M numeric $< > $(DUMP)
	@echo "Disassembly: $(DUMP)"

clean:
	rm -rf $(BUILD)
