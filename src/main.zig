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
    rects.deinit();
    defer _ = gpa.deinit();
    defer app.core.deinit();
}

var mouse_x: f64 = 0.0;
var mouse_y: f64 = 0.0;

const Rect = struct {
    x: f32, y: f32, col: [4]f32 = [_]f32{0.0, 0.0, 0.0, 1.0},
};

var rects: std.ArrayList(Rect) = std.ArrayList(Rect).init(gpa.allocator());

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
                if(key_event.key == .r){
                    try rects.append(
                        Rect{.x = @floatCast(f32, mouse_x), .y = @floatCast(f32, mouse_y),
                            .col = [_]f32{1.0, 0.0, 0.0, 1.0}}
                    );
                }
                else if(key_event.key == .g){
                    try rects.append(
                        Rect{.x = @floatCast(f32, mouse_x), .y = @floatCast(f32, mouse_y),
                            .col = [_]f32{0.0, 1.0, 0.0, 1.0}}
                    );
                }
                else if(key_event.key == .b){
                    try rects.append(
                        Rect{.x = @floatCast(f32, mouse_x), .y = @floatCast(f32, mouse_y),
                            .col = [_]f32{0.0, 0.0, 1.0, 1.0}}
                    );
                }

                if(key_event.key == .c){
                    rects.clearRetainingCapacity();
                }
            },
            else => {},
        }
    }

    try app.renderer.begin();

    // for (rects.items) |rect|{
    //     app.renderer.setColor(rect.col[0], rect.col[1], rect.col[2], rect.col[3]);
    //     try app.renderer.drawRectangle(rect.x, rect.y, 300.0, 100.0, 5.0);   
    // }
    app.renderer.setColor(0.235, 0.22, 0.212, 1.0);
    try app.renderer.drawFilledRectangle(150.0, 150.0, 100.0, 100.0);

    app.renderer.setColor(0.984, 0.286, 0.204, 1.0);
    try app.renderer.drawRectangle(350.0, 150.0, 100.0, 100.0, 50.0);

    app.renderer.setColor(0.722, 0.733, 0.149, 1.0);
    try app.renderer.drawRectangle(150.0, 350.0, 100.0, 100.0, 30.0);

    app.renderer.setColor(0.514, 0.647, 0.596, 1.0);
    try app.renderer.drawFilledRectangle(350.0, 350.0, 100.0, 100.0);

    try app.renderer.end();

    return false;
}
