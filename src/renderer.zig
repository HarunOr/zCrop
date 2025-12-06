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
    // Zoom/pan state
    user_scale: f32,
    fit_scale: f32,
    pan_x: f32,
    pan_y: f32,
    is_user_zoomed: bool,

    const Self = @This();

    // Zoom constants
    const MIN_SCALE: f32 = 0.1;
    const MAX_SCALE: f32 = 10.0;
    const ZOOM_STEP: f32 = 1.2;
    pub const PAN_STEP: f32 = 50.0;

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
            .user_scale = 1.0,
            .fit_scale = 1.0,
            .pan_x = 0.0,
            .pan_y = 0.0,
            .is_user_zoomed = false,
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

        // Store fit scale (never upscale beyond 1.0 for fit)
        self.fit_scale = @min(@min(scale_x, scale_y), 1.0);

        // Use fit scale if user hasn't manually zoomed
        if (!self.is_user_zoomed) {
            self.scale = self.fit_scale;
            self.pan_x = 0.0;
            self.pan_y = 0.0;
        } else {
            self.scale = self.user_scale;
        }

        self.updateOffsets();
    }

    fn updateOffsets(self: *Self) void {
        const scaled_width = @as(f32, @floatFromInt(self.image_width)) * self.scale;
        const scaled_height = @as(f32, @floatFromInt(self.image_height)) * self.scale;

        // Center the image, then apply pan offset
        const base_x = (@as(f32, @floatFromInt(self.window_width)) - scaled_width) / 2.0;
        const base_y = (@as(f32, @floatFromInt(self.window_height)) - scaled_height) / 2.0;

        // Pan offset is in image pixels, convert to screen pixels
        self.offset_x = @intFromFloat(base_x - self.pan_x * self.scale);
        self.offset_y = @intFromFloat(base_y - self.pan_y * self.scale);
    }

    /// Zoom centered on a specific screen position
    pub fn zoomAtPoint(self: *Self, screen_x: i32, screen_y: i32, zoom_in: bool) void {
        // Get image coordinates under cursor before zoom
        const img_pos = self.screenToImage(screen_x, screen_y);

        // Calculate new scale
        const factor = if (zoom_in) ZOOM_STEP else 1.0 / ZOOM_STEP;
        const new_scale = std.math.clamp(self.scale * factor, MIN_SCALE, MAX_SCALE);

        if (new_scale == self.scale) return; // At limit

        self.user_scale = new_scale;
        self.scale = new_scale;
        self.is_user_zoomed = true;

        // Calculate new pan to keep the same image point under cursor
        // We want: screen_x = img_pos.x * scale + offset_x
        // Where: offset_x = base_x - pan_x * scale
        // So: pan_x = (base_x - (screen_x - img_pos.x * scale)) / scale
        const scaled_width = @as(f32, @floatFromInt(self.image_width)) * self.scale;
        const scaled_height = @as(f32, @floatFromInt(self.image_height)) * self.scale;
        const base_x = (@as(f32, @floatFromInt(self.window_width)) - scaled_width) / 2.0;
        const base_y = (@as(f32, @floatFromInt(self.window_height)) - scaled_height) / 2.0;

        const target_offset_x = @as(f32, @floatFromInt(screen_x)) -
            @as(f32, @floatFromInt(img_pos.x)) * self.scale;
        const target_offset_y = @as(f32, @floatFromInt(screen_y)) -
            @as(f32, @floatFromInt(img_pos.y)) * self.scale;

        self.pan_x = (base_x - target_offset_x) / self.scale;
        self.pan_y = (base_y - target_offset_y) / self.scale;

        self.constrainPan();
        self.updateOffsets();
    }

    /// Reset to fit-to-window view
    pub fn resetZoom(self: *Self) void {
        self.is_user_zoomed = false;
        self.user_scale = 1.0;
        self.pan_x = 0.0;
        self.pan_y = 0.0;
        self.calculateLayout();
    }

    /// Apply pan delta (in image pixels)
    pub fn pan(self: *Self, delta_x: f32, delta_y: f32) void {
        self.pan_x += delta_x;
        self.pan_y += delta_y;
        self.constrainPan();
        self.updateOffsets();
    }

    /// Keep pan within reasonable bounds
    fn constrainPan(self: *Self) void {
        const scaled_width = @as(f32, @floatFromInt(self.image_width)) * self.scale;
        const scaled_height = @as(f32, @floatFromInt(self.image_height)) * self.scale;
        const window_w = @as(f32, @floatFromInt(self.window_width));
        const window_h = @as(f32, @floatFromInt(self.window_height));

        // Allow panning such that at least some of the image remains visible
        const margin_x = @max(scaled_width * 0.1, 50.0);
        const margin_y = @max(scaled_height * 0.1, 50.0);

        const max_pan_x = (scaled_width + window_w) / 2.0 / self.scale - margin_x / self.scale;
        const max_pan_y = (scaled_height + window_h) / 2.0 / self.scale - margin_y / self.scale;

        self.pan_x = std.math.clamp(self.pan_x, -max_pan_x, max_pan_x);
        self.pan_y = std.math.clamp(self.pan_y, -max_pan_y, max_pan_y);
    }

    /// Check if panning should be enabled (image larger than window)
    pub fn canPan(self: Self) bool {
        const scaled_width = @as(f32, @floatFromInt(self.image_width)) * self.scale;
        const scaled_height = @as(f32, @floatFromInt(self.image_height)) * self.scale;
        return scaled_width > @as(f32, @floatFromInt(self.window_width)) or
            scaled_height > @as(f32, @floatFromInt(self.window_height));
    }

    pub fn handleResize(self: *Self, width: i32, height: i32) void {
        self.window_width = width;
        self.window_height = height;

        if (self.is_user_zoomed) {
            // Preserve user zoom, just update offsets
            self.updateOffsets();
        } else {
            // Recalculate fit scale
            self.calculateLayout();
        }
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
    zero,
    unknown,

    pub fn fromSDL(scancode: c.SDL_Scancode) Key {
        return switch (scancode) {
            c.SDL_SCANCODE_RETURN, c.SDL_SCANCODE_KP_ENTER => .enter,
            c.SDL_SCANCODE_ESCAPE => .escape,
            c.SDL_SCANCODE_R => .r,
            c.SDL_SCANCODE_0, c.SDL_SCANCODE_KP_0 => .zero,
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
    mouse_wheel: struct { x: i32, y: i32, delta_y: i32, ctrl: bool, shift: bool },
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
        c.SDL_MOUSEWHEEL => blk: {
            // Get current mouse position
            var mx: c_int = 0;
            var my: c_int = 0;
            _ = c.SDL_GetMouseState(&mx, &my);

            // Get modifier state
            const mod_state = c.SDL_GetModState();
            const ctrl = (mod_state & c.KMOD_CTRL) != 0;
            const shift = (mod_state & c.KMOD_SHIFT) != 0;

            break :blk InputEvent{
                .mouse_wheel = .{
                    .x = mx,
                    .y = my,
                    .delta_y = event.wheel.y,
                    .ctrl = ctrl,
                    .shift = shift,
                },
            };
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
