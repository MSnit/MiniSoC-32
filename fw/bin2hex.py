#!/usr/bin/env python3
import sys

if len(sys.argv) < 3:
    print(f"Usage: {sys.argv[0]} <input.bin> <output.hex> [num_words]")
    sys.exit(1)

with open(sys.argv[1], 'rb') as f:
    data = f.read()

# pad to multiple of 4
if len(data) % 4 != 0:
    data += b'\x00' * (4 - len(data) % 4)

max_words = int(sys.argv[3]) if len(sys.argv) > 3 else 1024

with open(sys.argv[2], 'w') as f:
    for i in range(0, len(data), 4):
        word = data[i] | (data[i+1] << 8) | (data[i+2] << 16) | (data[i+3] << 24)
        f.write(f"{word:08x}\n")
    # pad remaining memory with NOP (0x00000013)
    remaining = max_words - (len(data) // 4)
    for _ in range(max(0, remaining)):
        f.write("00000013\n")
