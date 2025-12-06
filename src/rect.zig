const std = @import("std");

/// A rectangle defined by its top-left corner and dimensions.
pub const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    const Self = @This();
    pub const MIN_SIZE: i32 = 10;

    /// Create a rectangle from two corner points.
    /// Normalizes to ensure width/height are positive.
    pub fn fromPoints(x1: i32, y1: i32, x2: i32, y2: i32) Self {
        const min_x = @min(x1, x2);
        const max_x = @max(x1, x2);
        const min_y = @min(y1, y2);
        const max_y = @max(y1, y2);

        return Self{
            .x = min_x,
            .y = min_y,
            .width = max_x - min_x,
            .height = max_y - min_y,
        };
    }

    /// Create a rectangle centered at a point with given dimensions.
    pub fn centered(center_x: i32, center_y: i32, w: i32, h: i32) Self {
        return Self{
            .x = center_x - @divFloor(w, 2),
            .y = center_y - @divFloor(h, 2),
            .width = w,
            .height = h,
        };
    }

    pub fn right(self: Self) i32 {
        return self.x + self.width;
    }

    pub fn bottom(self: Self) i32 {
        return self.y + self.height;
    }

    pub fn center(self: Self) struct { x: i32, y: i32 } {
        return .{
            .x = self.x + @divFloor(self.width, 2),
            .y = self.y + @divFloor(self.height, 2),
        };
    }

    pub fn contains(self: Self, px: i32, py: i32) bool {
        return px >= self.x and px < self.right() and
            py >= self.y and py < self.bottom();
    }

    pub fn isValid(self: Self) bool {
        return self.width >= MIN_SIZE and self.height >= MIN_SIZE;
    }

    /// Represents which part of the rectangle was clicked for drag behavior.
    pub const HitZone = enum {
        none,
        inside,
        top_left,
        top_right,
        bottom_left,
        bottom_right,
        top,
        bottom,
        left,
        right,

        pub fn isCorner(self: HitZone) bool {
            return switch (self) {
                .top_left, .top_right, .bottom_left, .bottom_right => true,
                else => false,
            };
        }

        pub fn isEdge(self: HitZone) bool {
            return switch (self) {
                .top, .bottom, .left, .right => true,
                else => false,
            };
        }
    };

    /// Test which part of the rectangle a point hits.
    pub fn hitTest(self: Self, px: i32, py: i32, handle_size: i32) HitZone {
        const hs = handle_size;

        // Check corners first (they overlap with edges)
        if (self.inCornerArea(px, py, self.x, self.y, hs)) return .top_left;
        if (self.inCornerArea(px, py, self.right(), self.y, hs)) return .top_right;
        if (self.inCornerArea(px, py, self.x, self.bottom(), hs)) return .bottom_left;
        if (self.inCornerArea(px, py, self.right(), self.bottom(), hs)) return .bottom_right;

        // Check edges
        if (py >= self.y - hs and py <= self.y + hs and px >= self.x and px <= self.right()) return .top;
        if (py >= self.bottom() - hs and py <= self.bottom() + hs and px >= self.x and px <= self.right()) return .bottom;
        if (px >= self.x - hs and px <= self.x + hs and py >= self.y and py <= self.bottom()) return .left;
        if (px >= self.right() - hs and px <= self.right() + hs and py >= self.y and py <= self.bottom()) return .right;

        if (self.contains(px, py)) return .inside;

        return .none;
    }

    fn inCornerArea(self: Self, px: i32, py: i32, corner_x: i32, corner_y: i32, size: i32) bool {
        _ = self;
        const dx = px - corner_x;
        const dy = py - corner_y;
        return (if (dx < 0) -dx else dx) <= size and (if (dy < 0) -dy else dy) <= size;
    }

    pub fn translate(self: *Self, dx: i32, dy: i32) void {
        self.x += dx;
        self.y += dy;
    }

    /// Resize based on which edge/corner is being dragged.
    pub fn resize(self: *Self, zone: HitZone, new_x: i32, new_y: i32) void {
        switch (zone) {
            .top_left => {
                const new_right = self.right();
                const new_bottom = self.bottom();
                self.x = @min(new_x, new_right - MIN_SIZE);
                self.y = @min(new_y, new_bottom - MIN_SIZE);
                self.width = new_right - self.x;
                self.height = new_bottom - self.y;
            },
            .top_right => {
                const new_bottom = self.bottom();
                self.width = @max(MIN_SIZE, new_x - self.x);
                self.y = @min(new_y, new_bottom - MIN_SIZE);
                self.height = new_bottom - self.y;
            },
            .bottom_left => {
                const new_right = self.right();
                self.x = @min(new_x, new_right - MIN_SIZE);
                self.width = new_right - self.x;
                self.height = @max(MIN_SIZE, new_y - self.y);
            },
            .bottom_right => {
                self.width = @max(MIN_SIZE, new_x - self.x);
                self.height = @max(MIN_SIZE, new_y - self.y);
            },
            .top => {
                const new_bottom = self.bottom();
                self.y = @min(new_y, new_bottom - MIN_SIZE);
                self.height = new_bottom - self.y;
            },
            .bottom => {
                self.height = @max(MIN_SIZE, new_y - self.y);
            },
            .left => {
                const new_right = self.right();
                self.x = @min(new_x, new_right - MIN_SIZE);
                self.width = new_right - self.x;
            },
            .right => {
                self.width = @max(MIN_SIZE, new_x - self.x);
            },
            .inside, .none => {},
        }
    }

    /// Constrain the rectangle to fit within bounds.
    pub fn constrain(self: Self, max_width: i32, max_height: i32) Self {
        var result = self;

        result.width = @min(result.width, max_width);
        result.height = @min(result.height, max_height);

        result.x = @max(0, @min(result.x, max_width - result.width));
        result.y = @max(0, @min(result.y, max_height - result.height));

        return result;
    }

    /// Convert to unsigned values for array indexing.
    pub fn toUnsigned(self: Self) ?struct { x: u32, y: u32, width: u32, height: u32 } {
        if (self.x < 0 or self.y < 0 or self.width < 0 or self.height < 0) {
            return null;
        }
        return .{
            .x = @intCast(self.x),
            .y = @intCast(self.y),
            .width = @intCast(self.width),
            .height = @intCast(self.height),
        };
    }
};

test "Rect.fromPoints normalizes coordinates" {
    const rect = Rect.fromPoints(100, 100, 50, 50);

    try std.testing.expectEqual(@as(i32, 50), rect.x);
    try std.testing.expectEqual(@as(i32, 50), rect.y);
    try std.testing.expectEqual(@as(i32, 50), rect.width);
    try std.testing.expectEqual(@as(i32, 50), rect.height);
}

test "Rect.contains works correctly" {
    const rect = Rect{ .x = 10, .y = 10, .width = 100, .height = 50 };

    try std.testing.expect(rect.contains(50, 30));
    try std.testing.expect(rect.contains(10, 10));

    try std.testing.expect(!rect.contains(9, 30));
    try std.testing.expect(!rect.contains(111, 30));
    try std.testing.expect(!rect.contains(50, 60));
}

test "Rect.hitTest identifies zones correctly" {
    const rect = Rect{ .x = 100, .y = 100, .width = 200, .height = 100 };
    const hs: i32 = 10;

    try std.testing.expectEqual(Rect.HitZone.top_left, rect.hitTest(100, 100, hs));
    try std.testing.expectEqual(Rect.HitZone.top_right, rect.hitTest(300, 100, hs));
    try std.testing.expectEqual(Rect.HitZone.bottom_left, rect.hitTest(100, 200, hs));
    try std.testing.expectEqual(Rect.HitZone.bottom_right, rect.hitTest(300, 200, hs));

    try std.testing.expectEqual(Rect.HitZone.inside, rect.hitTest(200, 150, hs));

    try std.testing.expectEqual(Rect.HitZone.none, rect.hitTest(0, 0, hs));
}

test "Rect.resize maintains minimum size" {
    var rect = Rect{ .x = 100, .y = 100, .width = 50, .height = 50 };

    rect.resize(.bottom_right, 100, 100);

    try std.testing.expect(rect.width >= Rect.MIN_SIZE);
    try std.testing.expect(rect.height >= Rect.MIN_SIZE);
}

test "Rect.constrain keeps rectangle in bounds" {
    const rect = Rect{ .x = 900, .y = 500, .width = 200, .height = 200 };
    const constrained = rect.constrain(1000, 600);

    try std.testing.expect(constrained.right() <= 1000);
    try std.testing.expect(constrained.bottom() <= 600);
    try std.testing.expect(constrained.x >= 0);
    try std.testing.expect(constrained.y >= 0);
}
