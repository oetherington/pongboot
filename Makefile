all: build

build:
	nasm pong.S -f bin -o pong.bin
	@size=$$(stat --printf="%s" pong.bin 2>/dev/null || stat -f%z pong.bin); \
		test "$$size" -eq 512

clean:
	rm -f pong.bin

dump:
	ndisasm -b 16 -o 0x7c00 pong.bin

run:
	qemu-system-x86_64 -drive format=raw,file=pong.bin
