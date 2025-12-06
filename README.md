# zCrop

A simple image cropping tool built with Zig.

## Features

- Load PNG, JPEG, and BMP images
- Interactive crop rectangle with mouse drag-and-resize
- Visual overlay showing crop region
- Save cropped image to disk

## Requirements

- **Zig** 0.15.0 or later
- **SDL2** development libraries

### Installing SDL2

```bash
# Arch Linux
sudo pacman -S sdl2

# Ubuntu/Debian
sudo apt install libsdl2-dev

# macOS
brew install sdl2

# Windows (vcpkg)
vcpkg install sdl2
```

## Building

```bash
# Using Make (recommended)
make              # Build optimized release binary
make debug        # Build debug binary
make test         # Run tests
make run IMG=photo.png  # Build and run with image
make install      # Install to ~/.local/bin
make clean        # Remove build artifacts

# Using Zig directly
zig build -Doptimize=ReleaseSmall  # Optimized (~130KB)
zig build                           # Debug build
zig build test                      # Run tests
zig build run -- path/to/image.png  # Build and run
```

## Usage

```bash
zCrop image.png
# or
./zig-out/bin/zCrop image.png
```

### Controls

| Key/Action | Description |
|------------|-------------|
| **Mouse drag** | Draw a new crop rectangle or resize existing one |
| **Drag inside** | Move the crop rectangle |
| **Drag corners/edges** | Resize the crop rectangle |
| **Enter** | Crop and save, then exit |
| **R** | Reset crop to full image |
| **Escape** | Quit without saving |

The cropped image is saved as `originalname_cropped.ext` in the same directory.

## Libraries Used

- **[stb_image](https://github.com/nothings/stb)** - Single-header C library for image loading/saving. Chosen for simplicity and to demonstrate Zig's C interop.
- **[SDL2](https://libsdl.org/)** - Cross-platform windowing, input, and rendering. Mature and widely available.

## License

MIT
