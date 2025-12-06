const std = @import("std");
const Allocator = std.mem.Allocator;
const Image = @import("image.zig").Image;
const Rect = @import("rect.zig").Rect;

pub const CropError = error{
    InvalidRegion,
    OutOfBounds,
    OutOfMemory,
};

pub fn cropImage(allocator: Allocator, source: Image, region: Rect) CropError!Image {
    const bounds = region.toUnsigned() orelse return CropError.InvalidRegion;

    if (bounds.x + bounds.width > source.width or
        bounds.y + bounds.height > source.height)
    {
        return CropError.OutOfBounds;
    }

    var dest = Image.create(allocator, bounds.width, bounds.height, source.original_channels) catch return CropError.OutOfMemory;
    errdefer dest.deinit();

    const src_stride = source.width * 4;
    const dst_stride = bounds.width * 4;

    var y: u32 = 0;
    while (y < bounds.height) : (y += 1) {
        const src_row_start = (bounds.y + y) * src_stride + bounds.x * 4;
        const dst_row_start = y * dst_stride;

        const src_slice = source.pixels[src_row_start .. src_row_start + dst_stride];
        const dst_slice = dest.pixels[dst_row_start .. dst_row_start + dst_stride];

        @memcpy(dst_slice, src_slice);
    }

    return dest;
}

pub fn cropImageInPlace(image: *Image, region: Rect) CropError!void {
    const bounds = region.toUnsigned() orelse return CropError.InvalidRegion;

    if (bounds.x + bounds.width > image.width or
        bounds.y + bounds.height > image.height)
    {
        return CropError.OutOfBounds;
    }

    if (bounds.x == 0 and bounds.y == 0 and
        bounds.width == image.width and bounds.height == image.height)
    {
        return;
    }

    const src_stride = image.width * 4;
    const dst_stride = bounds.width * 4;

    var y: u32 = 0;
    while (y < bounds.height) : (y += 1) {
        const src_row_start = (bounds.y + y) * src_stride + bounds.x * 4;
        const dst_row_start = y * dst_stride;

        if (src_row_start != dst_row_start) {
            const src_slice = image.pixels[src_row_start .. src_row_start + dst_stride];
            const dst_slice = image.pixels[dst_row_start .. dst_row_start + dst_stride];

            for (dst_slice, src_slice) |*dst, src| {
                dst.* = src;
            }
        }
    }

    image.width = bounds.width;
    image.height = bounds.height;
}

pub fn aspectRatio(width: u32, height: u32) f32 {
    if (height == 0) return 0;
    return @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
}

pub fn constrainAspectRatio(rect: Rect, target_ratio: f32) Rect {
    if (target_ratio <= 0 or rect.width <= 0 or rect.height <= 0) {
        return rect;
    }

    var result = rect;
    const current_ratio = @as(f32, @floatFromInt(rect.width)) / @as(f32, @floatFromInt(rect.height));

    if (current_ratio > target_ratio) {
        result.width = @intFromFloat(@as(f32, @floatFromInt(rect.height)) * target_ratio);
    } else {
        result.height = @intFromFloat(@as(f32, @floatFromInt(rect.width)) / target_ratio);
    }

    return result;
}

test "cropImage creates correct dimensions" {
    const allocator = std.testing.allocator;

    var source = try Image.create(allocator, 100, 100, 4);
    defer source.deinit();

    var y: u32 = 0;
    while (y < 100) : (y += 1) {
        var x: u32 = 0;
        while (x < 100) : (x += 1) {
            source.setPixel(x, y, .{
                .r = @truncate(x),
                .g = @truncate(y),
                .b = 128,
                .a = 255,
            });
        }
    }

    const region = Rect{ .x = 20, .y = 30, .width = 50, .height = 40 };
    var cropped = try cropImage(allocator, source, region);
    defer cropped.deinit();

    try std.testing.expectEqual(@as(u32, 50), cropped.width);
    try std.testing.expectEqual(@as(u32, 40), cropped.height);

    const pixel = cropped.getPixel(0, 0).?;
    try std.testing.expectEqual(@as(u8, 20), pixel.r);
    try std.testing.expectEqual(@as(u8, 30), pixel.g);
}

test "cropImage returns error for out of bounds" {
    const allocator = std.testing.allocator;

    var source = try Image.create(allocator, 100, 100, 4);
    defer source.deinit();

    const region = Rect{ .x = 80, .y = 80, .width = 50, .height = 50 };
    const result = cropImage(allocator, source, region);

    try std.testing.expectError(CropError.OutOfBounds, result);
}

test "cropImage returns error for negative coordinates" {
    const allocator = std.testing.allocator;

    var source = try Image.create(allocator, 100, 100, 4);
    defer source.deinit();

    const region = Rect{ .x = -10, .y = 10, .width = 50, .height = 50 };
    const result = cropImage(allocator, source, region);

    try std.testing.expectError(CropError.InvalidRegion, result);
}

test "constrainAspectRatio maintains ratio" {
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };

    const constrained = constrainAspectRatio(rect, 16.0 / 9.0);

    const ratio = @as(f32, @floatFromInt(constrained.width)) /
        @as(f32, @floatFromInt(constrained.height));

    try std.testing.expect(@abs(ratio - 16.0 / 9.0) < 0.1);
}
