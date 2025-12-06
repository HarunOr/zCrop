.PHONY: build release debug run test clean install

# Default target
build: release

# Release build (optimized, small binary)
release:
	zig build -Doptimize=ReleaseSmall

# Debug build (with symbols and safety checks)
debug:
	zig build

# Run with an image file
# Usage: make run IMG=path/to/image.png
run: release
	./zig-out/bin/zcrop $(IMG)

# Run tests
test:
	zig build test

# Clean build artifacts
clean:
	rm -rf zig-out .zig-cache

# Install to ~/.local/bin
install: release
	cp zig-out/bin/zcrop ~/.local/bin/
