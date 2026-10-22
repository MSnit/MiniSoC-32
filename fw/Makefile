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
LDFLAGS  = $(ARCH) -nostdlib -T link.ld

BUILD    = build
PROG    ?= main
TARGET   = $(BUILD)/$(PROG)

DEMOS    = main demo_blink demo_uart demo_spi demo_timer_irq self_test

.PHONY: all clean dump demos

all: $(BUILD)/minisoc.hex

demos: $(foreach d, $(DEMOS), $(BUILD)/$(d).hex)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/startup.o: src/startup.S | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.elf: $(BUILD)/startup.o $(BUILD)/%.o
	$(CC) $(LDFLAGS) -Wl,-Map=$(BUILD)/$*.map $^ -o $@

$(BUILD)/%.bin: $(BUILD)/%.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/%.hex: $(BUILD)/%.bin
	python3 bin2hex.py $< $@ 1024
	@echo "Built: $@"

$(BUILD)/minisoc.hex: $(BUILD)/main.hex
	cp $< $@

dump: $(BUILD)/$(PROG).elf
	$(OBJDUMP) -d -M numeric $< > $(BUILD)/$(PROG).dump
	@echo "Disassembly: $(BUILD)/$(PROG).dump"

clean:
	rm -rf $(BUILD)
