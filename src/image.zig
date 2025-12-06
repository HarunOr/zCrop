const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

pub const Image = struct {
    pixels: []u8,
    width: u32,
    height: u32,
    channels: u32,
    original_channels: u32,
    allocator: Allocator,
    source: enum { zig_allocated, stb_allocated },

    const Self = @This();

    pub fn loadFromFile(allocator: Allocator, path: []const u8) !Self {
        const c_path = try allocator.allocSentinel(u8, path.len, 0);
        defer allocator.free(c_path);
        @memcpy(c_path, path);

        var width: c_int = 0;
        var height: c_int = 0;
        var channels: c_int = 0;

        const data_ptr = c.stbi_load(c_path.ptr, &width, &height, &channels, 4);

        if (data_ptr == null) {
            return error.ImageLoadFailed;
        }

        const w: u32 = @intCast(width);
        const h: u32 = @intCast(height);
        const size = w * h * 4;

        const pixels: []u8 = data_ptr[0..size];

        return Self{
            .pixels = pixels,
            .width = w,
            .height = h,
            .channels = 4,
            .original_channels = @intCast(channels),
            .allocator = allocator,
            .source = .stb_allocated,
        };
    }

    pub fn create(allocator: Allocator, width: u32, height: u32, original_channels: u32) !Self {
        const size = width * height * 4;
        const pixels = try allocator.alloc(u8, size);
        @memset(pixels, 0);

        return Self{
            .pixels = pixels,
            .width = width,
            .height = height,
            .channels = 4,
            .original_channels = original_channels,
            .allocator = allocator,
            .source = .zig_allocated,
        };
    }

    pub fn getPixel(self: Self, x: u32, y: u32) ?Color {
        if (x >= self.width or y >= self.height) {
            return null;
        }

        const idx = (y * self.width + x) * 4;
        return Color{
            .r = self.pixels[idx],
            .g = self.pixels[idx + 1],
            .b = self.pixels[idx + 2],
            .a = self.pixels[idx + 3],
        };
    }

    pub fn setPixel(self: *Self, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) {
            return;
        }

        const idx = (y * self.width + x) * 4;
        self.pixels[idx] = color.r;
        self.pixels[idx + 1] = color.g;
        self.pixels[idx + 2] = color.b;
        self.pixels[idx + 3] = color.a;
    }

    pub fn getRow(self: Self, y: u32) ?[]u8 {
        if (y >= self.height) {
            return null;
        }

        const start = y * self.width * 4;
        const end = start + self.width * 4;
        return self.pixels[start..end];
    }

    pub fn saveToFile(self: Self, path: []const u8) !void {
        const c_path = try self.allocator.allocSentinel(u8, path.len, 0);
        defer self.allocator.free(c_path);
        @memcpy(c_path, path);

        const w: c_int = @intCast(self.width);
        const h: c_int = @intCast(self.height);

        // Determine output channels (JPEG max 3, no alpha)
        const is_jpeg = std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg");
        const save_ch: u32 = if (is_jpeg) @min(self.original_channels, 3) else self.original_channels;

        // Convert RGBA to target channel count
        const converted = try self.allocator.alloc(u8, self.width * self.height * save_ch);
        defer self.allocator.free(converted);

        for (0..self.width * self.height) |i| {
            for (0..save_ch) |ch| {
                converted[i * save_ch + ch] = self.pixels[i * 4 + ch];
            }
        }

        const ch: c_int = @intCast(save_ch);

        // Set max PNG compression (default is 8, max is 9)
        c.stbi_write_png_compression_level = 9;

        const result = if (std.mem.endsWith(u8, path, ".png"))
            c.stbi_write_png(c_path.ptr, w, h, ch, converted.ptr, w * ch)
        else if (is_jpeg)
            c.stbi_write_jpg(c_path.ptr, w, h, ch, converted.ptr, 80)
        else if (std.mem.endsWith(u8, path, ".bmp"))
            c.stbi_write_bmp(c_path.ptr, w, h, ch, converted.ptr)
        else
            return error.UnsupportedFormat;

        if (result == 0) {
            return error.ImageSaveFailed;
        }

        // Try to optimize PNG with system tools (best-effort, ignore failures)
        if (std.mem.endsWith(u8, path, ".png")) {
            optimizePng(self.allocator, path);
        }
    }

    fn optimizePng(allocator: Allocator, path: []const u8) void {
        // Try oxipng first (best), then optipng, then pngcrush
        const optimizers = [_]struct { cmd: []const u8, args: []const []const u8 }{
            .{ .cmd = "oxipng", .args = &.{ "-o", "max", "-s", "-q" } },
            .{ .cmd = "optipng", .args = &.{ "-o7", "-quiet" } },
            .{ .cmd = "pngcrush", .args = &.{ "-q", "-ow" } },
        };

        for (optimizers) |opt| {
            // Build argv array
            var argv_buf: [8][]const u8 = undefined;
            var argc: usize = 0;

            argv_buf[argc] = opt.cmd;
            argc += 1;
            for (opt.args) |arg| {
                if (argc < argv_buf.len - 1) {
                    argv_buf[argc] = arg;
                    argc += 1;
                }
            }
            argv_buf[argc] = path;
            argc += 1;

            var child = std.process.Child.init(argv_buf[0..argc], allocator);
            child.spawn() catch continue;
            _ = child.wait() catch continue;
            return; // Success with this optimizer
        }
    }

    pub fn deinit(self: *Self) void {
        switch (self.source) {
            .stb_allocated => {
                c.stbi_image_free(self.pixels.ptr);
            },
            .zig_allocated => {
                self.allocator.free(self.pixels);
            },
        }
        self.* = undefined;
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    pub fn fromHex(hex: u32) Color {
        return Color{
            .r = @truncate(hex >> 24),
            .g = @truncate(hex >> 16),
            .b = @truncate(hex >> 8),
            .a = @truncate(hex),
        };
    }
};

test "Color.fromHex creates correct color" {
    const color = Color.fromHex(0xFF8040FF);
    try std.testing.expectEqual(@as(u8, 255), color.r);
    try std.testing.expectEqual(@as(u8, 128), color.g);
    try std.testing.expectEqual(@as(u8, 64), color.b);
    try std.testing.expectEqual(@as(u8, 255), color.a);
}

test "Image.create allocates correct size" {
    const allocator = std.testing.allocator;
    var img = try Image.create(allocator, 100, 50, 4);
    defer img.deinit();

    try std.testing.expectEqual(@as(u32, 100), img.width);
    try std.testing.expectEqual(@as(u32, 50), img.height);
    try std.testing.expectEqual(@as(usize, 100 * 50 * 4), img.pixels.len);
}

test "Image.setPixel and getPixel roundtrip" {
    const allocator = std.testing.allocator;
    var img = try Image.create(allocator, 10, 10, 4);
    defer img.deinit();

    const test_color = Color{ .r = 100, .g = 150, .b = 200, .a = 255 };
    img.setPixel(5, 5, test_color);

    const retrieved = img.getPixel(5, 5).?;
    try std.testing.expectEqual(test_color.r, retrieved.r);
    try std.testing.expectEqual(test_color.g, retrieved.g);
    try std.testing.expectEqual(test_color.b, retrieved.b);
    try std.testing.expectEqual(test_color.a, retrieved.a);
}

test "Image.getPixel returns null for out of bounds" {
    const allocator = std.testing.allocator;
    var img = try Image.create(allocator, 10, 10, 4);
    defer img.deinit();

    try std.testing.expect(img.getPixel(10, 0) == null);
    try std.testing.expect(img.getPixel(0, 10) == null);
    try std.testing.expect(img.getPixel(100, 100) == null);
}
