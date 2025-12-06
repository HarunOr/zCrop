const std = @import("std");
const Image = @import("image.zig").Image;
const Rect = @import("rect.zig").Rect;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const Renderer = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: ?*c.SDL_Texture,
    window_width: i32,
    window_height: i32,
    image_width: i32,
    image_height: i32,
    offset_x: i32,
    offset_y: i32,
    scale: f32,

    const Self = @This();

    pub fn init(title: [*:0]const u8, width: i32, height: i32) !Self {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            return error.SDLInitFailed;
        }
        errdefer c.SDL_Quit();

        const window = c.SDL_CreateWindow(
            title,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            width,
            height,
            c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        ) orelse return error.WindowCreationFailed;
        errdefer c.SDL_DestroyWindow(window);

        const renderer = c.SDL_CreateRenderer(
            window,
            -1,
            c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
        ) orelse return error.RendererCreationFailed;

        _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

        return Self{
            .window = window,
            .renderer = renderer,
            .texture = null,
            .window_width = width,
            .window_height = height,
            .image_width = 0,
            .image_height = 0,
            .offset_x = 0,
            .offset_y = 0,
            .scale = 1.0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.texture) |tex| {
            c.SDL_DestroyTexture(tex);
        }
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    pub fn setImage(self: *Self, image: Image) !void {
        if (self.texture) |tex| {
            c.SDL_DestroyTexture(tex);
            self.texture = null;
        }

        const texture = c.SDL_CreateTexture(
            self.renderer,
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STATIC,
            @intCast(image.width),
            @intCast(image.height),
        ) orelse return error.TextureCreationFailed;

        const result = c.SDL_UpdateTexture(
            texture,
            null,
            image.pixels.ptr,
            @intCast(image.width * 4),
        );

        if (result != 0) {
            c.SDL_DestroyTexture(texture);
            return error.TextureUpdateFailed;
        }

        self.texture = texture;
        self.image_width = @intCast(image.width);
        self.image_height = @intCast(image.height);

        self.calculateLayout();
    }

    fn calculateLayout(self: *Self) void {
        if (self.image_width == 0 or self.image_height == 0) return;

        const padding: i32 = 40;
        const available_width = self.window_width - padding * 2;
        const available_height = self.window_height - padding * 2;

        const scale_x = @as(f32, @floatFromInt(available_width)) /
            @as(f32, @floatFromInt(self.image_width));
        const scale_y = @as(f32, @floatFromInt(available_height)) /
            @as(f32, @floatFromInt(self.image_height));

        self.scale = @min(scale_x, scale_y);
        self.scale = @min(self.scale, 1.0);

        const scaled_width: i32 = @intFromFloat(@as(f32, @floatFromInt(self.image_width)) * self.scale);
        const scaled_height: i32 = @intFromFloat(@as(f32, @floatFromInt(self.image_height)) * self.scale);

        self.offset_x = @divFloor(self.window_width - scaled_width, 2);
        self.offset_y = @divFloor(self.window_height - scaled_height, 2);
    }

    pub fn handleResize(self: *Self, width: i32, height: i32) void {
        self.window_width = width;
        self.window_height = height;
        self.calculateLayout();
    }

    pub fn screenToImage(self: Self, screen_x: i32, screen_y: i32) struct { x: i32, y: i32 } {
        const x = @as(f32, @floatFromInt(screen_x - self.offset_x)) / self.scale;
        const y = @as(f32, @floatFromInt(screen_y - self.offset_y)) / self.scale;
        return .{
            .x = @intFromFloat(x),
            .y = @intFromFloat(y),
        };
    }

    pub fn imageToScreen(self: Self, img_x: i32, img_y: i32) struct { x: i32, y: i32 } {
        return .{
            .x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(img_x)) * self.scale)) + self.offset_x,
            .y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(img_y)) * self.scale)) + self.offset_y,
        };
    }

    pub fn imageRectToScreen(self: Self, rect: Rect) Rect {
        const top_left = self.imageToScreen(rect.x, rect.y);
        const bottom_right = self.imageToScreen(rect.right(), rect.bottom());
        return Rect.fromPoints(top_left.x, top_left.y, bottom_right.x, bottom_right.y);
    }

    pub fn clear(self: Self) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, 40, 40, 40, 255);
        _ = c.SDL_RenderClear(self.renderer);
    }

    pub fn renderImage(self: Self) void {
        const texture = self.texture orelse return;

        const dest = c.SDL_Rect{
            .x = self.offset_x,
            .y = self.offset_y,
            .w = @intFromFloat(@as(f32, @floatFromInt(self.image_width)) * self.scale),
            .h = @intFromFloat(@as(f32, @floatFromInt(self.image_height)) * self.scale),
        };

        _ = c.SDL_RenderCopy(self.renderer, texture, null, &dest);
    }

    pub fn renderCropOverlay(self: Self, crop_rect: Rect, is_active: bool) void {
        const screen_rect = self.imageRectToScreen(crop_rect);

        self.renderDarkenedRegions(screen_rect);

        const border_color: struct { r: u8, g: u8, b: u8 } = if (is_active)
            .{ .r = 255, .g = 200, .b = 0 }
        else
            .{ .r = 255, .g = 255, .b = 255 };

        _ = c.SDL_SetRenderDrawColor(self.renderer, border_color.r, border_color.g, border_color.b, 255);

        const sdl_rect = c.SDL_Rect{
            .x = screen_rect.x,
            .y = screen_rect.y,
            .w = screen_rect.width,
            .h = screen_rect.height,
        };
        _ = c.SDL_RenderDrawRect(self.renderer, &sdl_rect);

        self.renderHandles(screen_rect, border_color.r, border_color.g, border_color.b);
    }

    fn renderDarkenedRegions(self: Self, crop: Rect) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 128);

        const img_left = self.offset_x;
        const img_top = self.offset_y;
        const img_right = self.offset_x + @as(i32, @intFromFloat(@as(f32, @floatFromInt(self.image_width)) * self.scale));
        const img_bottom = self.offset_y + @as(i32, @intFromFloat(@as(f32, @floatFromInt(self.image_height)) * self.scale));

        if (crop.y > img_top) {
            const rect = c.SDL_Rect{ .x = img_left, .y = img_top, .w = img_right - img_left, .h = crop.y - img_top };
            _ = c.SDL_RenderFillRect(self.renderer, &rect);
        }

        if (crop.bottom() < img_bottom) {
            const rect = c.SDL_Rect{ .x = img_left, .y = crop.bottom(), .w = img_right - img_left, .h = img_bottom - crop.bottom() };
            _ = c.SDL_RenderFillRect(self.renderer, &rect);
        }

        if (crop.x > img_left) {
            const rect = c.SDL_Rect{ .x = img_left, .y = crop.y, .w = crop.x - img_left, .h = crop.height };
            _ = c.SDL_RenderFillRect(self.renderer, &rect);
        }

        if (crop.right() < img_right) {
            const rect = c.SDL_Rect{ .x = crop.right(), .y = crop.y, .w = img_right - crop.right(), .h = crop.height };
            _ = c.SDL_RenderFillRect(self.renderer, &rect);
        }
    }

    fn renderHandles(self: Self, rect: Rect, r: u8, g: u8, b: u8) void {
        const handle_size: i32 = 8;
        const half: i32 = @divFloor(handle_size, 2);

        _ = c.SDL_SetRenderDrawColor(self.renderer, r, g, b, 255);

        const corners = [_]struct { x: i32, y: i32 }{
            .{ .x = rect.x, .y = rect.y },
            .{ .x = rect.right(), .y = rect.y },
            .{ .x = rect.x, .y = rect.bottom() },
            .{ .x = rect.right(), .y = rect.bottom() },
        };

        for (corners) |corner| {
            const handle = c.SDL_Rect{
                .x = corner.x - half,
                .y = corner.y - half,
                .w = handle_size,
                .h = handle_size,
            };
            _ = c.SDL_RenderFillRect(self.renderer, &handle);
        }

        const edges = [_]struct { x: i32, y: i32 }{
            .{ .x = rect.x + @divFloor(rect.width, 2), .y = rect.y },
            .{ .x = rect.x + @divFloor(rect.width, 2), .y = rect.bottom() },
            .{ .x = rect.x, .y = rect.y + @divFloor(rect.height, 2) },
            .{ .x = rect.right(), .y = rect.y + @divFloor(rect.height, 2) },
        };

        for (edges) |edge| {
            const handle = c.SDL_Rect{
                .x = edge.x - half,
                .y = edge.y - half,
                .w = handle_size,
                .h = handle_size,
            };
            _ = c.SDL_RenderFillRect(self.renderer, &handle);
        }
    }

    pub fn setStatus(self: Self, status: [*:0]const u8) void {
        c.SDL_SetWindowTitle(self.window, status);
    }

    pub fn present(self: Self) void {
        c.SDL_RenderPresent(self.renderer);
    }

    pub fn renderLoadingCircle(self: Self, elapsed_ms: u64) void {
        const center_x = @divFloor(self.window_width, 2);
        const center_y = @divFloor(self.window_height, 2);
        const radius: i32 = 40;
        const segment_count: u32 = 12;
        const segment_length: i32 = 12;
        const segment_width: i32 = 4;

        const rotation_period_ms: u64 = 1000;
        const active_segment = @as(u32, @intCast((elapsed_ms % rotation_period_ms) * segment_count / rotation_period_ms));

        var i: u32 = 0;
        while (i < segment_count) : (i += 1) {
            const segments_behind = (active_segment + segment_count - i) % segment_count;
            const alpha: u8 = if (segments_behind < 4)
                @as(u8, @intCast(255 - segments_behind * 50))
            else
                55;

            const angle = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(segment_count)));

            const inner_x = center_x + @as(i32, @intFromFloat(@cos(angle) * @as(f32, @floatFromInt(radius - segment_length))));
            const inner_y = center_y + @as(i32, @intFromFloat(@sin(angle) * @as(f32, @floatFromInt(radius - segment_length))));
            const outer_x = center_x + @as(i32, @intFromFloat(@cos(angle) * @as(f32, @floatFromInt(radius))));
            const outer_y = center_y + @as(i32, @intFromFloat(@sin(angle) * @as(f32, @floatFromInt(radius))));

            _ = c.SDL_SetRenderDrawColor(self.renderer, 255, 200, 0, alpha);

            var w: i32 = -@divFloor(segment_width, 2);
            while (w <= @divFloor(segment_width, 2)) : (w += 1) {
                const perp_x = @as(i32, @intFromFloat(-@sin(angle) * @as(f32, @floatFromInt(w))));
                const perp_y = @as(i32, @intFromFloat(@cos(angle) * @as(f32, @floatFromInt(w))));
                _ = c.SDL_RenderDrawLine(
                    self.renderer,
                    inner_x + perp_x,
                    inner_y + perp_y,
                    outer_x + perp_x,
                    outer_y + perp_y,
                );
            }
        }
    }
};

pub const Key = enum {
    enter,
    escape,
    r,
    unknown,

    pub fn fromSDL(scancode: c.SDL_Scancode) Key {
        return switch (scancode) {
            c.SDL_SCANCODE_RETURN, c.SDL_SCANCODE_KP_ENTER => .enter,
            c.SDL_SCANCODE_ESCAPE => .escape,
            c.SDL_SCANCODE_R => .r,
            else => .unknown,
        };
    }
};

pub const InputEvent = union(enum) {
    quit,
    key_down: Key,
    mouse_down: struct { x: i32, y: i32, button: MouseButton },
    mouse_up: struct { x: i32, y: i32, button: MouseButton },
    mouse_move: struct { x: i32, y: i32 },
    window_resize: struct { width: i32, height: i32 },
    none,
};

pub const MouseButton = enum {
    left,
    right,
    middle,
    other,

    pub fn fromSDL(button: u8) MouseButton {
        return switch (button) {
            c.SDL_BUTTON_LEFT => .left,
            c.SDL_BUTTON_RIGHT => .right,
            c.SDL_BUTTON_MIDDLE => .middle,
            else => .other,
        };
    }
};

pub fn pollEvent() InputEvent {
    var event: c.SDL_Event = undefined;

    if (c.SDL_PollEvent(&event) == 0) {
        return .none;
    }

    return switch (event.type) {
        c.SDL_QUIT => .quit,
        c.SDL_KEYDOWN => .{ .key_down = Key.fromSDL(event.key.keysym.scancode) },
        c.SDL_MOUSEBUTTONDOWN => .{
            .mouse_down = .{
                .x = event.button.x,
                .y = event.button.y,
                .button = MouseButton.fromSDL(event.button.button),
            },
        },
        c.SDL_MOUSEBUTTONUP => .{
            .mouse_up = .{
                .x = event.button.x,
                .y = event.button.y,
                .button = MouseButton.fromSDL(event.button.button),
            },
        },
        c.SDL_MOUSEMOTION => .{
            .mouse_move = .{
                .x = event.motion.x,
                .y = event.motion.y,
            },
        },
        c.SDL_WINDOWEVENT => blk: {
            if (event.window.event == c.SDL_WINDOWEVENT_RESIZED or
                event.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED)
            {
                break :blk InputEvent{
                    .window_resize = .{
                        .width = event.window.data1,
                        .height = event.window.data2,
                    },
                };
            }
            break :blk .none;
        },
        else => .none,
    };
}
