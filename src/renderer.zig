const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");

const RendererError = error{
    BufferCapacityExceeded,
};

const max_vertices: u32 = 6 * 1000 + 3 * 1000; // 1000 rect + 1000 tris

pub const Vertex = extern struct {
    pos: @Vector(4, f32),
    col: @Vector(4, f32),
};

pub const Renderer = struct {
    core: *mach.Core,
    pipeline: *gpu.RenderPipeline,
    queue: *gpu.Queue,
    vertex_buffer: *gpu.Buffer,
    vertices: [max_vertices]Vertex = undefined,
    vertices_len: u32 = 0,
    color: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },

    pub fn init(core: *mach.Core) Renderer {
        const shader_module = core.device().createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));

        const blend = gpu.BlendState{};
        const color_target = gpu.ColorTargetState{ .format = core.descriptor().format, .blend = &blend, .write_mask = gpu.ColorWriteMaskFlags.all };

        const fragment = gpu.FragmentState.init(.{ .module = shader_module, .entry_point = "frag_main", .targets = &.{color_target} });

        const vertex_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x4, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x4, .offset = @offsetOf(Vertex, "col"), .shader_location = 1 },
        };

        const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(Vertex),
            .step_mode = .vertex,
            .attributes = &vertex_attributes,
        });

        const vertex_buffer = core.device().createBuffer(&.{
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = @sizeOf(Vertex) * max_vertices,
        });

        const vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vert_main",
            .buffers = &.{vertex_buffer_layout},
        });

        const pipeline_desc = gpu.RenderPipeline.Descriptor{
            .fragment = &fragment,
            .vertex = vertex,
        };

        var pipeline = core.device().createRenderPipeline(&pipeline_desc);
        var queue = core.device().getQueue();

        shader_module.release();

        return Renderer{
            .core = core,
            .pipeline = pipeline,
            .queue = queue,
            .vertex_buffer = vertex_buffer,
        };
    }

    pub fn begin(renderer: *Renderer) !void {
        renderer.vertices_len = 0;
    }

    pub fn end(renderer: *Renderer) !void {
        renderer.queue.writeBuffer(renderer.vertex_buffer, 0, renderer.vertices[0..]);

        const back_buffer_view = renderer.core.swapChain().getCurrentTextureView();
        const color_attachment = gpu.RenderPassColorAttachment{
            .view = back_buffer_view,
            .clear_value = std.mem.zeroes(gpu.Color),
            .load_op = .clear,
            .store_op = .store,
        };
        const command_encoder = renderer.core.device().createCommandEncoder(null);
        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });
        const pass = command_encoder.beginRenderPass(&render_pass_info);
        pass.setPipeline(renderer.pipeline);
        pass.setVertexBuffer(0, renderer.vertex_buffer, 0, @sizeOf(Vertex) * renderer.vertices_len);
        pass.draw(renderer.vertices_len, 1, 0, 0);
        pass.end();
        pass.release();

        var command = command_encoder.finish(null);
        command_encoder.release();
        renderer.queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        renderer.core.swapChain().present();
        back_buffer_view.release();
    }

    pub fn drawRectangle(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32, thiccness: f32) !void {
        const half_thicc: f32 = thiccness / 2.0;
        try renderer.drawFilledRectangle(x - half_thicc, y - half_thicc, width + thiccness, thiccness);
        try renderer.drawFilledRectangle(x + width - half_thicc, y - half_thicc, thiccness, height + thiccness);
        try renderer.drawFilledRectangle(x - half_thicc, y + height - half_thicc, width + thiccness, thiccness);
        try renderer.drawFilledRectangle(x - half_thicc, y - half_thicc, thiccness, height + thiccness);
    }

    pub fn drawFilledRectangle(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32) !void {
        if (renderer.vertices_len >= max_vertices) return RendererError.BufferCapacityExceeded;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        const new_x = x / half_window_w - 1.0;
        const new_y = 1.0 - y / half_window_h;
        const new_width = width / half_window_w;
        const new_height = height / half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y, 0.1, 1.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y, 0.1, 1.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height, 0.1, 1.0 }, .col = renderer.color };

        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x, new_y - new_height, 0.1, 1.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 4] = .{ .pos = .{ new_x + new_width, new_y - new_height, 0.1, 1.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 5] = .{ .pos = .{ new_x + new_width, new_y, 0.1, 1.0 }, .col = renderer.color };
        renderer.vertices_len += 6;
    }

    pub fn drawFilledTriangle(renderer: *Renderer, x1: f32, y1: f32, x2:f32, y2:f32, x3:f32, y3: f32) !void {
        if(renderer.vertices_len >= max_vertices) return RendererError.BufferCapacityExceeded;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        const new_x1 = x1 / half_window_w - 1.0;
        const new_y1 = 1.0 - y1 / half_window_h;

        const new_x2 = x2 / half_window_w - 1.0;
        const new_y2 = 1.0 - y2 / half_window_h;

        const new_x3 = x3 / half_window_w - 1.0;
        const new_y3 = 1.0 - y3 / half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x1, new_y1, 0.0, 1.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x2, new_y2, 0.0, 1.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x3, new_y3, 0.0, 1.0 }, .col = renderer.color };

        renderer.vertices_len += 3;

    }

    pub fn setColor(renderer: *Renderer, r: f32, g: f32, b: f32, a: f32) void {
        renderer.color[0] = r;
        renderer.color[1] = g;
        renderer.color[2] = b;
        renderer.color[3] = a;
    }
};
