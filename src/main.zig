const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const Vertex = extern struct {
    pos: @Vector(4, f32),
    col: @Vector(4, f32),
};

const vertices = [_]Vertex{
    .{.pos = .{ 0.0, 0.5, 0.1, 1.0 }, .col = .{1.0, 1.0, 0.0, 1.0}},
    .{.pos = .{ -0.5, -0.5, 0.1, 1.0 }, .col = .{1.0, 1.0, 0.0, 1.0}},
    .{.pos = .{ 0.0, -0.5, 0.1, 1.0 }, .col = .{1.0, 1.0, 0.0, 1.0}},
};

core: mach.Core,
pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,
vertex_buffer: *gpu.Buffer,

pub fn init(app: *App) !void {
    try app.core.init(gpa.allocator(), .{});
    app.core.setTitle("yohohoho");

    const shader_module = app.core.device().createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));

    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{ .format = app.core.descriptor().format, .blend = &blend, .write_mask = gpu.ColorWriteMaskFlags.all };

    const fragment = gpu.FragmentState.init(.{ .module = shader_module, .entry_point = "frag_main", .targets = &.{color_target} });

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{.format = .float32x4, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0},
        .{.format = .float32x4, .offset = @offsetOf(Vertex, "col"), .shader_location = 1},
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attributes = &vertex_attributes,
    });

    const vertex_buffer = app.core.device().createBuffer(&.{
        .usage = .{.vertex = true},
        .size = @sizeOf(Vertex) * vertices.len,
        .mapped_at_creation = true,
    });

    var vertex_mapped = vertex_buffer.getMappedRange(Vertex, 0, vertices.len);
    std.mem.copy(Vertex, vertex_mapped.?, vertices[0..]);
    vertex_buffer.unmap();

    app.vertex_buffer = vertex_buffer;

    const vertex = gpu.VertexState.init(.{
        .module = shader_module,
        .entry_point = "vert_main",
        .buffers = &.{vertex_buffer_layout},
    });


    const pipeline_desc = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = vertex,
    };

    app.pipeline = app.core.device().createRenderPipeline(&pipeline_desc);
    app.queue = app.core.device().getQueue();

    shader_module.release();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();
}

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
    }

    const back_buffer_view = app.core.swapChain().getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };
    const command_encoder = app.core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = command_encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
    pass.draw(vertices.len, 1, 0, 0);
    pass.end();
    pass.release();

    var command = command_encoder.finish(null);
    command_encoder.release();
    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    app.core.swapChain().present();
    back_buffer_view.release();

    return false;
}
