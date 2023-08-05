const std = @import("std");
const core = @import("core");
const gpu = core.gpu;
const zigimg = @import("zigimg");

const Renderer = @import("renderer.zig").Renderer;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// core: mach.core,
renderer: Renderer,
random: std.rand.DefaultPrng,
texture: zigimg.Image = undefined,

pub fn init(app: *App) !void {
    try core.init(.{});
    core.setTitle("Khichdi2D");

    app.texture = try zigimg.Image.fromFilePath(gpa.allocator(), "src/mach.png");
    defer app.texture.deinit();
    app.renderer = try Renderer.init(gpa.allocator(), app.texture);
    app.random = std.rand.DefaultPrng.init(42);
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer core.deinit();
    app.renderer.deinit();
}

pub fn random_float(app: *App, min: f32, max: f32) f32 {
    const range = max - min;
    const random = app.random.random().float(f32) * range;
    return min + random;
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            .key_press => |key_event| {
                if (key_event.key == .space) {
                    // app.renderer.re_draw = true;
                }
            },
            else => {},
        }
    }

    app.renderer.re_draw = true;

    const width = @as(f32, @floatFromInt(core.size().width));
    const height = @as(f32, @floatFromInt(core.size().height));

    app.renderer.begin();

    for (0..4000) |_| {
        const x = app.random_float(0.0, width);
        const y = app.random_float(0.0, height);

        // if (i % 2 == 0) {
        // app.renderer.setColor(0.722, 0.733, 0.149, 0.7);
        // app.renderer.drawFilledRectangle(x, y, 10.0, 10.0);
        // } else {
        app.renderer.setColor(1.0, 1.0, 1.0, 0.7);
        app.renderer.drawScaledImage(x, y, 50.0, 50.0);
        // }
    }

    // app.renderer.setColor(0.235, 0.22, 0.212, 1.0);
    // app.renderer.drawFilledRectangle(100.0, 100.0, 400.0, 400.0);

    // app.renderer.setColor(0.984, 0.286, 0.204, 1.0);
    // app.renderer.drawRectangle(100.0, 100.0, 400.0, 400.0, 20.0);

    // app.renderer.setColor(0.722, 0.733, 0.149, 1.0);
    // app.renderer.drawFilledRectangle(150.0, 350.0, 100.0, 100.0);

    // app.renderer.setColor(1.0, 1.0, 1.0, 0.5);
    // app.renderer.drawScaledImage(300.0, 200.0, 100.0, 100.0);

    // app.renderer.setColor(0.514, 0.647, 0.596, 0.7);
    // app.renderer.drawFilledTriangle(250.0, 150.0, 450.0, 150.0, 450.0, 350.0);

    app.renderer.end();

    return false;
}
