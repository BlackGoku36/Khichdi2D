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

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
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

    try app.renderer.drawImage(100.0, 100.0, 100.0, 100.0);

    try app.renderer.drawImage(300.0, 100.0, 100.0, 100.0);

    try app.renderer.drawImage(100.0, 300.0, 100.0, 100.0);

    try app.renderer.drawImage(300.0, 300.0, 100.0, 100.0);

    try app.renderer.end();

    return false;
}
