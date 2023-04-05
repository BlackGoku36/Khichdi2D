const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;

const Renderer = @import("renderer.zig").Renderer;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
renderer: Renderer,
random: std.rand.DefaultPrng,

pub fn init(app: *App) !void {
    try app.core.init(gpa.allocator(), .{});
    app.core.setTitle("Khichdi2D");

    app.renderer = try Renderer.init(&app.core, gpa.allocator());
    app.random = std.rand.DefaultPrng.init(42);
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();
    app.renderer.deinit();
}


pub fn random_float(app:*App, min: f32, max: f32) f32 {
    const range = max - min;
    const random = app.random.random().float(f32) * range;
    return min + random;
}

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            .key_press => |key_event| {
                if(key_event.key == .space){
                    // app.renderer.re_draw = true;
                }
            },
            else => {},
        }
    }

    app.renderer.re_draw = true;

    const width = @intToFloat(f32, app.core.size().width);
    const height = @intToFloat(f32, app.core.size().height);

    app.renderer.begin();

    for (0..4000) |_| {
        const x = app.random_float(0.0,  width);
        const y = app.random_float(0.0,  height);

        // if (i % 2 == 0){
            // app.renderer.setColor(0.722, 0.733, 0.149, 1.0);
            // try app.renderer.drawFilledRectangle(x, y, 100.0, 100.0);
        // }else{
            app.renderer.setColor(1.0, 1.0, 1.0, 0.5);
            try app.renderer.drawScaledImage(x, y, 100.0, 100.0);
        // }
    }

    // app.renderer.setColor(0.235, 0.22, 0.212, 1.0);
    // try app.renderer.drawFilledRectangle(100.0, 100.0, 400.0, 400.0);

    // app.renderer.setColor(0.984, 0.286, 0.204, 1.0);
    // try app.renderer.drawRectangle(100.0, 100.0, 400.0, 400.0, 20.0);

    // app.renderer.setColor(0.722, 0.733, 0.149, 1.0);
    // try app.renderer.drawFilledRectangle(x, 350.0, 100.0, 100.0);
    
    // app.renderer.setColor(1.0, 1.0, 1.0, 0.5);
    // try app.renderer.drawScaledImage(300.0, 200.0, 100.0, 100.0);

    // app.renderer.setColor(0.514, 0.647, 0.596, 0.7);
    // try app.renderer.drawFilledTriangle(250.0, 150.0, 450.0, 150.0, 450.0, 350.0);

    app.renderer.end();

    return false;
}
