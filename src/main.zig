const std = @import("std");
const Image = @import("image.zig").Image;
const Color = @import("image.zig").Color;
const Rect = @import("rect.zig").Rect;
const crop_module = @import("crop.zig");
const renderer_module = @import("renderer.zig");
const Renderer = renderer_module.Renderer;
const InputEvent = renderer_module.InputEvent;
const Key = renderer_module.Key;

const SaveResult = union(enum) {
    success: []const u8,
    failure,
};

const AppState = struct {
    image: ?Image,
    crop_rect: Rect,
    is_dragging: bool,
    drag_zone: Rect.HitZone,
    drag_start_x: i32,
    drag_start_y: i32,
    drag_initial_rect: Rect,
    file_path: ?[]const u8,
    allocator: std.mem.Allocator,
    // Saving state
    is_saving: bool,
    save_thread: ?std.Thread,
    save_result: ?SaveResult,
    save_start_time: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .image = null,
            .crop_rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 },
            .is_dragging = false,
            .drag_zone = .none,
            .drag_start_x = 0,
            .drag_start_y = 0,
            .drag_initial_rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 },
            .file_path = null,
            .allocator = allocator,
            .is_saving = false,
            .save_thread = null,
            .save_result = null,
            .save_start_time = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.image) |*img| {
            img.deinit();
        }
        if (self.file_path) |path| {
            self.allocator.free(path);
        }
    }

    pub fn loadImage(self: *Self, path: []const u8) !void {
        if (self.image) |*img| {
            img.deinit();
        }

        if (self.file_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.file_path = try self.allocator.dupe(u8, path);

        self.image = try Image.loadFromFile(self.allocator, path);

        const img = self.image.?;
        self.crop_rect = Rect{
            .x = 0,
            .y = 0,
            .width = @intCast(img.width),
            .height = @intCast(img.height),
        };
    }

    pub fn cropAndSave(self: *Self) ![]const u8 {
        const img = self.image orelse return error.NoImage;

        var cropped = try crop_module.cropImage(self.allocator, img, self.crop_rect);
        defer cropped.deinit();

        const output_path = try self.generateOutputPath();

        try cropped.saveToFile(output_path);

        return output_path;
    }

    fn generateOutputPath(self: *Self) ![]const u8 {
        const path = self.file_path orelse return error.NoFilePath;

        const ext_pos = std.mem.lastIndexOf(u8, path, ".") orelse path.len;

        const base = path[0..ext_pos];
        const ext = if (ext_pos < path.len) path[ext_pos..] else ".png";

        return try std.fmt.allocPrint(self.allocator, "{s}_cropped{s}", .{ base, ext });
    }

    pub fn resetCrop(self: *Self) void {
        if (self.image) |img| {
            self.crop_rect = Rect{
                .x = 0,
                .y = 0,
                .width = @intCast(img.width),
                .height = @intCast(img.height),
            };
        }
    }

    pub fn startSaveThread(self: *Self) void {
        self.is_saving = true;
        self.save_result = null;
        self.save_start_time = std.time.milliTimestamp();
        self.save_thread = std.Thread.spawn(.{}, saveWorker, .{self}) catch null;
    }

    fn saveWorker(self: *Self) void {
        const output_path = self.cropAndSave() catch {
            self.save_result = .failure;
            return;
        };
        self.save_result = .{ .success = output_path };
    }

    pub fn checkSaveComplete(self: *Self) ?SaveResult {
        if (self.save_thread) |thread| {
            if (self.save_result != null) {
                thread.join();
                self.save_thread = null;
                self.is_saving = false;
                return self.save_result;
            }
        }
        return null;
    }

    pub fn getElapsedSaveTime(self: Self) u64 {
        if (!self.is_saving) return 0;
        const now = std.time.milliTimestamp();
        return @intCast(now - self.save_start_time);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print(
            \\Usage: zcrop <image_file>
            \\
            \\Controls:
            \\  Mouse drag    - Draw/resize crop area
            \\  Enter         - Crop and save
            \\  R             - Reset crop to full image
            \\  Escape        - Quit without saving
            \\
            \\Supported formats: PNG, JPEG, BMP
            \\
        , .{});
        return;
    }

    var state = AppState.init(allocator);
    defer state.deinit();

    state.loadImage(args[1]) catch |err| {
        std.debug.print("Failed to load image '{s}': {}\n", .{ args[1], err });
        return;
    };

    const img = state.image.?;
    std.debug.print("Loaded image: {}x{} pixels\n", .{ img.width, img.height });

    const max_window: i32 = 1200;
    const window_width = @min(@as(i32, @intCast(img.width)) + 80, max_window);
    const window_height = @min(@as(i32, @intCast(img.height)) + 80, max_window);

    var rend = Renderer.init(
        "zcrop - Press Enter to crop, Escape to quit",
        window_width,
        window_height,
    ) catch |err| {
        std.debug.print("Failed to initialize renderer: {}\n", .{err});
        return;
    };
    defer rend.deinit();

    try rend.setImage(img);

    var running = true;
    while (running) {
        while (true) {
            const event = renderer_module.pollEvent();
            switch (event) {
                .quit => {
                    running = false;
                },
                .key_down => |key| {
                    switch (key) {
                        .escape => {
                            running = false;
                        },
                        .enter => {
                            if (!state.is_saving) {
                                rend.setStatus("zcrop - Saving...");
                                state.startSaveThread();
                            }
                        },
                        .r => {
                            state.resetCrop();
                        },
                        else => {},
                    }
                },
                .mouse_down => |mouse| {
                    if (mouse.button == .left) {
                        handleMouseDown(&state, &rend, mouse.x, mouse.y);
                    }
                },
                .mouse_up => |mouse| {
                    if (mouse.button == .left) {
                        handleMouseUp(&state);
                    }
                },
                .mouse_move => |mouse| {
                    handleMouseMove(&state, &rend, mouse.x, mouse.y);
                },
                .window_resize => |resize| {
                    rend.handleResize(resize.width, resize.height);
                },
                .none => break,
            }
        }

        // Check if save completed
        if (state.checkSaveComplete()) |result| {
            switch (result) {
                .success => |output_path| {
                    std.debug.print("Saved cropped image to: {s}\n", .{output_path});
                    rend.setStatus("zcrop - Saved!");
                    allocator.free(output_path);
                    running = false;
                },
                .failure => {
                    std.debug.print("Failed to save image\n", .{});
                    rend.setStatus("zcrop - Save failed!");
                },
            }
        }

        rend.clear();
        rend.renderImage();
        rend.renderCropOverlay(state.crop_rect, state.is_dragging);

        // Render loading spinner during save
        if (state.is_saving) {
            rend.renderLoadingCircle(state.getElapsedSaveTime());
        }

        rend.present();

        std.Thread.sleep(1_000_000);
    }
}

fn handleMouseDown(state: *AppState, rend: *Renderer, screen_x: i32, screen_y: i32) void {
    const img_pos = rend.screenToImage(screen_x, screen_y);

    const zone = state.crop_rect.hitTest(img_pos.x, img_pos.y, 10);

    if (zone != .none) {
        state.is_dragging = true;
        state.drag_zone = zone;
        state.drag_start_x = img_pos.x;
        state.drag_start_y = img_pos.y;
        state.drag_initial_rect = state.crop_rect;
    } else {
        state.is_dragging = true;
        state.drag_zone = .bottom_right;
        state.crop_rect = Rect{
            .x = img_pos.x,
            .y = img_pos.y,
            .width = 1,
            .height = 1,
        };
        state.drag_start_x = img_pos.x;
        state.drag_start_y = img_pos.y;
    }
}

fn handleMouseUp(state: *AppState) void {
    state.is_dragging = false;
    state.drag_zone = .none;

    if (!state.crop_rect.isValid()) {
        state.resetCrop();
    }

    if (state.image) |img| {
        state.crop_rect = state.crop_rect.constrain(
            @intCast(img.width),
            @intCast(img.height),
        );
    }
}

fn handleMouseMove(state: *AppState, rend: *Renderer, screen_x: i32, screen_y: i32) void {
    if (!state.is_dragging) return;

    const img_pos = rend.screenToImage(screen_x, screen_y);

    switch (state.drag_zone) {
        .inside => {
            const dx = img_pos.x - state.drag_start_x;
            const dy = img_pos.y - state.drag_start_y;

            state.crop_rect.x = state.drag_initial_rect.x + dx;
            state.crop_rect.y = state.drag_initial_rect.y + dy;
        },
        .none => {},
        else => {
            state.crop_rect.resize(state.drag_zone, img_pos.x, img_pos.y);
        },
    }
}

test {
    _ = @import("image.zig");
    _ = @import("rect.zig");
    _ = @import("crop.zig");
}
