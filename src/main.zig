const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");

const Renderer = @import("renderer.zig").Renderer;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
renderer: Renderer,

pub fn init(app: *App) !void {
    try app.core.init(gpa.allocator(), .{});

    app.core.setTitle("yohohoho");

    app.renderer = Renderer.init(gpa.allocator(), &app.core);
}

pub fn deinit(app: *App) void {
    app.renderer.deinit();
    defer _ = gpa.deinit();
    defer app.core.deinit();
}

var mouse_x: f64 = 0.0;
var mouse_y: f64 = 0.0;

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            .mouse_motion => |mouse_motion|{
                mouse_x = mouse_motion.pos.x;
                mouse_y = mouse_motion.pos.y;
            },
            .key_press => |key_event|{
                if(key_event.key == .space){
                    try app.renderer.drawFilledRectangle(@floatCast(f32, mouse_x), @floatCast(f32, mouse_y), 10.0, 10.0);
                }
            },
            else => {},
        }
    }

    try app.renderer.render();

    return false;
}
