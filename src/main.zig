const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;

const ImageRenderer = @import("renderer.zig").ImageRenderer;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
renderer: ImageRenderer,

pub fn init(app: *App) !void {
    try app.core.init(gpa.allocator(), .{});
    app.core.setTitle("yohohoho");

    app.renderer = try ImageRenderer.init(&app.core, gpa.allocator());
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();
    app.renderer.deinit();
}

var mouse_x: f64 = 0.0;
var mouse_y: f64 = 0.0;

var x: f32 = 100.0;
var y: f32 = 100.0;

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            .mouse_motion => |mouse| {
                mouse_x = mouse.pos.x;
                mouse_y = mouse.pos.y;
            },
            else => {},
        }
    }

    try app.renderer.begin();

    // app.renderer.setColor(0.235, 0.22, 0.212, 1.0);
    // try app.renderer.drawFilledRectangle(100.0, 100.0, 400.0, 400.0);

    // app.renderer.setColor(0.984, 0.286, 0.204, 1.0);
    // try app.renderer.drawRectangle(100.0, 100.0, 400.0, 400.0, 20.0);

    // app.renderer.setColor(0.722, 0.733, 0.149, 1.0);
    // try app.renderer.drawFilledRectangle(150.0, 350.0, 100.0, 100.0);

    // app.renderer.setColor(0.514, 0.647, 0.596, 1.0);
    // try app.renderer.drawFilledTriangle(250.0, 150.0, 450.0, 150.0, 450.0, 350.0);

    // try app.renderer.drawImage(0.0, 100.0);

    // try app.renderer.drawScaledImage(500.0, 100.0, 100.0, 100.0);
    if (mouse_x > 100.0 and mouse_x < 100.0 + 400.0 and mouse_y > 100.0 and mouse_y < 100.0 + 400.0) {
        x = @floatCast(f32, mouse_x) - 100.0;
        y = @floatCast(f32, mouse_y) - 100.0;
    }

    try app.renderer.drawSubImage(100.0, 100.0, x, y, 200.0, 200.0);

    // try app.renderer.drawScaledSubImage(100.0, 100.0, 50.0, 50.0, 200.0, 200.0, 200.0, 200.0);

    try app.renderer.end();

    return false;
}
