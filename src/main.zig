const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;

const Renderer = @import("renderer.zig").Renderer;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
renderer: Renderer,
fps_timer: mach.Timer,
frames_counter: u8 = 0,

pub fn init(app: *App) !void {
    try app.core.init(gpa.allocator(), .{});
    app.core.setTitle("Khichdi2D");

    app.fps_timer = try mach.Timer.start();
    app.renderer = try Renderer.init(&app.core, gpa.allocator());
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();
    app.renderer.deinit();
}

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            .mouse_motion => |_| {
            },
            else => {},
        }
    }

    const delta_time = app.fps_timer.lap();

    app.renderer.begin();

    app.renderer.setColor(0.235, 0.22, 0.212, 1.0);
    try app.renderer.drawFilledRectangle(100.0, 100.0, 400.0, 400.0);

    app.renderer.setColor(0.984, 0.286, 0.204, 1.0);
    try app.renderer.drawRectangle(100.0, 100.0, 400.0, 400.0, 20.0);

    app.renderer.setColor(0.722, 0.733, 0.149, 1.0);
    try app.renderer.drawFilledRectangle(150.0, 350.0, 100.0, 100.0);
    
    app.renderer.setColor(1.0, 1.0, 1.0, 0.5);
    try app.renderer.drawScaledImage(300.0, 200.0, 100.0, 100.0);

    app.renderer.setColor(0.514, 0.647, 0.596, 1.0);
    try app.renderer.drawFilledTriangle(250.0, 150.0, 450.0, 150.0, 450.0, 350.0);

    app.renderer.end();

    if(app.frames_counter >= 100){
        var buf: [32]u8 = undefined;
        const title = try std.fmt.bufPrintZ(&buf, "Khichdi2D [ FPS: {d} ]", .{@floor(1 / delta_time)});
        app.core.setTitle(title);
        app.frames_counter = 0;
    }

    app.frames_counter += 1;

    return false;
}
