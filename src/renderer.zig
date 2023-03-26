const std = @import("std");
const mach = @import("mach");
const zigimg = @import("zigimg");
const gpu = mach.gpu;

const raw_img = @embedFile("mach.png");

const RendererError = error{
    BufferCapacityExceeded,
};

const max_vertices_colored: u32 = 6 * 1000 + 3 * 1000; // 1000 rect + 1000 tris
const max_vertices_images: u32 = 6 * 1000; // 1000 images

pub const ImageVertex = extern struct {
    pos: @Vector(2, f32),
    uv: @Vector(2, f32),
};

pub const ImageRenderer = struct {
    core: *mach.Core,
    pipeline: *gpu.RenderPipeline,
    queue: *gpu.Queue,
    vertex_buffer: *gpu.Buffer,
    vertices: [max_vertices_images]ImageVertex = undefined,
    vertices_len: u32 = 0,
    bind_group: *gpu.BindGroup,
    texture: *gpu.Texture,

    pub fn init(core: *mach.Core, allocator: std.mem.Allocator) !ImageRenderer {
        const shader_module = core.device().createShaderModuleWGSL("image_shader.wgsl", @embedFile("image_shader.wgsl"));

        const blend = gpu.BlendState{};
        const color_target = gpu.ColorTargetState{ .format = core.descriptor().format, .blend = &blend, .write_mask = gpu.ColorWriteMaskFlags.all };

        const fragment = gpu.FragmentState.init(.{ .module = shader_module, .entry_point = "frag_main", .targets = &.{color_target} });

        const vertex_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x2, .offset = @offsetOf(ImageVertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x2, .offset = @offsetOf(ImageVertex, "uv"), .shader_location = 1 },
        };

        const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(ImageVertex),
            .step_mode = .vertex,
            .attributes = &vertex_attributes,
        });

        const vertex_buffer = core.device().createBuffer(&.{
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = @sizeOf(ImageVertex) * max_vertices_images,
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

        var img = try zigimg.Image.fromMemory(allocator, raw_img);
        defer img.deinit();

        const img_size = gpu.Extent3D{ .width = @intCast(u32, img.width), .height = @intCast(u32, img.height) };
        const texture = core.device().createTexture(&.{
            .size = img_size,
            .format = .rgba8_unorm,
            .usage = .{
                .texture_binding = true,
                .copy_dst = true,
                .render_attachment = true,
            },
        });
        const texture_data_layout = gpu.Texture.DataLayout{
            .bytes_per_row = @intCast(u32, img.width * 4),
            .rows_per_image = @intCast(u32, img.height),
        };

        const sampler = core.device().createSampler(&.{
            .mag_filter = .linear,
            .min_filter = .linear,
        });

        switch (img.pixels) {
            .rgba32 => |pixels| queue.writeTexture(&.{ .texture = texture }, &texture_data_layout, &img_size, pixels),
            .rgb24 => |pixels| {
                const data = try rgb24ToRgba32(allocator, pixels);
                defer data.deinit(allocator);
                queue.writeTexture(&.{ .texture = texture }, &texture_data_layout, &img_size, data.rgba32);
            },
            else => @panic("unsupported image color format"),
        }

        const bind_group = core.device().createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = pipeline.getBindGroupLayout(0), .entries = &.{ gpu.BindGroup.Entry.sampler(0, sampler), gpu.BindGroup.Entry.textureView(1, texture.createView(&gpu.TextureView.Descriptor{})) } }));

        shader_module.release();

        return ImageRenderer{
            .core = core,
            .pipeline = pipeline,
            .queue = queue,
            .vertex_buffer = vertex_buffer,
            .bind_group = bind_group,
            .texture = texture,
        };
    }

    pub fn deinit(renderer: *ImageRenderer) void {
        renderer.bind_group.release();
    }

    pub fn begin(renderer: *ImageRenderer) !void {
        renderer.vertices_len = 0;
    }

    pub fn end(renderer: *ImageRenderer) !void {
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
        pass.setVertexBuffer(0, renderer.vertex_buffer, 0, @sizeOf(ImageVertex) * renderer.vertices_len);
        pass.setBindGroup(0, renderer.bind_group, &.{});
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

    pub fn drawImage(renderer: *ImageRenderer, x: f32, y: f32) !void {
        if (renderer.vertices_len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        const new_x = x / half_window_w - 1.0;
        const new_y = 1.0 - y / half_window_h;
        const new_width = @intToFloat(f32, renderer.texture.getWidth()) / half_window_w;
        const new_height = @intToFloat(f32, renderer.texture.getHeight()) / half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ 1.0, 0.0 } };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .uv = .{ 0.0, 0.0 } };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ 0.0, 1.0 } };

        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ 0.0, 1.0 } };
        renderer.vertices[renderer.vertices_len + 4] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ 1.0, 1.0 } };
        renderer.vertices[renderer.vertices_len + 5] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ 1.0, 0.0 } };
        renderer.vertices_len += 6;
    }

    pub fn drawSubImage(renderer: *ImageRenderer, x: f32, y: f32, x1: f32, y1: f32, width1: f32, height1: f32) !void {
        if (renderer.vertices_len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        const new_x = x / half_window_w - 1.0;
        const new_y = 1.0 - y / half_window_h;
        const new_width = @intToFloat(f32, renderer.texture.getWidth()) / half_window_w;
        const new_height = @intToFloat(f32, renderer.texture.getHeight()) / half_window_h;

        const sub_x = x1 / @intToFloat(f32, renderer.texture.getWidth());
        const sub_y = y1 / @intToFloat(f32, renderer.texture.getHeight());
        const sub_width = width1 / @intToFloat(f32, renderer.texture.getWidth());
        const sub_height = height1 / @intToFloat(f32, renderer.texture.getHeight());

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ sub_x + sub_width, sub_y } };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .uv = .{ sub_x, sub_y } };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ sub_x, sub_y + sub_height } };

        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ sub_x, sub_y + sub_height } };
        renderer.vertices[renderer.vertices_len + 4] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ sub_x + sub_width, sub_y + sub_height } };
        renderer.vertices[renderer.vertices_len + 5] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ sub_x + sub_width, sub_y } };
        renderer.vertices_len += 6;
    }

    pub fn drawScaledImage(renderer: *ImageRenderer, x: f32, y: f32, width: f32, height: f32) !void {
        if (renderer.vertices_len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        const new_x = x / half_window_w - 1.0;
        const new_y = 1.0 - y / half_window_h;
        const new_width = width / half_window_w;
        const new_height = height / half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ 1.0, 0.0 } };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .uv = .{ 0.0, 0.0 } };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ 0.0, 1.0 } };

        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ 0.0, 1.0 } };
        renderer.vertices[renderer.vertices_len + 4] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ 1.0, 1.0 } };
        renderer.vertices[renderer.vertices_len + 5] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ 1.0, 0.0 } };
        renderer.vertices_len += 6;
    }

    pub fn drawScaledSubImage(renderer: *ImageRenderer, x: f32, y: f32, width: f32, height: f32, x1: f32, y1: f32, width1: f32, height1: f32) !void {
        if (renderer.vertices_len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        const new_x = x / half_window_w - 1.0;
        const new_y = 1.0 - y / half_window_h;
        const new_width = width / half_window_w;
        const new_height = height / half_window_h;

        const sub_x = x1 / @intToFloat(f32, renderer.texture.getWidth());
        const sub_y = y1 / @intToFloat(f32, renderer.texture.getHeight());
        const sub_width = width1 / @intToFloat(f32, renderer.texture.getWidth());
        const sub_height = height1 / @intToFloat(f32, renderer.texture.getHeight());

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ sub_x + sub_width, sub_y } };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .uv = .{ sub_x, sub_y } };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ sub_x, sub_y + sub_height } };

        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ sub_x, sub_y + sub_height } };
        renderer.vertices[renderer.vertices_len + 4] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ sub_x + sub_width, sub_y + sub_height } };
        renderer.vertices[renderer.vertices_len + 5] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ sub_x + sub_width, sub_y } };
        renderer.vertices_len += 6;
    }

    fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
        const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
        var i: usize = 0;
        while (i < in.len) : (i += 1) {
            out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
        }
        return out;
    }
};

pub const ColorVertex = extern struct {
    pos: @Vector(2, f32),
    col: @Vector(4, f32),
};

pub const ColoredRenderer = struct {
    core: *mach.Core,
    pipeline: *gpu.RenderPipeline,
    queue: *gpu.Queue,
    vertex_buffer: *gpu.Buffer,
    vertices: [max_vertices_colored]ColorVertex = undefined,
    vertices_len: u32 = 0,
    color: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },

    pub fn init(core: *mach.Core) ColoredRenderer {
        const shader_module = core.device().createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));

        const blend = gpu.BlendState{};
        const color_target = gpu.ColorTargetState{ .format = core.descriptor().format, .blend = &blend, .write_mask = gpu.ColorWriteMaskFlags.all };

        const fragment = gpu.FragmentState.init(.{ .module = shader_module, .entry_point = "frag_main", .targets = &.{color_target} });

        const vertex_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x2, .offset = @offsetOf(ColorVertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x4, .offset = @offsetOf(ColorVertex, "col"), .shader_location = 1 },
        };

        const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(ColorVertex),
            .step_mode = .vertex,
            .attributes = &vertex_attributes,
        });

        const vertex_buffer = core.device().createBuffer(&.{
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = @sizeOf(ColorVertex) * max_vertices_colored,
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

        return ColoredRenderer{
            .core = core,
            .pipeline = pipeline,
            .queue = queue,
            .vertex_buffer = vertex_buffer,
        };
    }

    pub fn begin(renderer: *ColoredRenderer) !void {
        renderer.vertices_len = 0;
    }

    pub fn end(renderer: *ColoredRenderer) !void {
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
        pass.setVertexBuffer(0, renderer.vertex_buffer, 0, @sizeOf(ColorVertex) * renderer.vertices_len);
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

    pub fn drawRectangle(renderer: *ColoredRenderer, x: f32, y: f32, width: f32, height: f32, thiccness: f32) !void {
        const half_thicc: f32 = thiccness / 2.0;
        try renderer.drawFilledRectangle(x - half_thicc, y - half_thicc, width + thiccness, thiccness);
        try renderer.drawFilledRectangle(x + width - half_thicc, y - half_thicc, thiccness, height + thiccness);
        try renderer.drawFilledRectangle(x - half_thicc, y + height - half_thicc, width + thiccness, thiccness);
        try renderer.drawFilledRectangle(x - half_thicc, y - half_thicc, thiccness, height + thiccness);
    }

    pub fn drawFilledRectangle(renderer: *ColoredRenderer, x: f32, y: f32, width: f32, height: f32) !void {
        if (renderer.vertices_len >= max_vertices_colored) return RendererError.BufferCapacityExceeded;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        const new_x = x / half_window_w - 1.0;
        const new_y = 1.0 - y / half_window_h;
        const new_width = width / half_window_w;
        const new_height = height / half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .col = renderer.color };

        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x, new_y - new_height }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 4] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 5] = .{ .pos = .{ new_x + new_width, new_y }, .col = renderer.color };
        renderer.vertices_len += 6;
    }

    pub fn drawFilledTriangle(renderer: *ColoredRenderer, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) !void {
        if (renderer.vertices_len >= max_vertices_colored) return RendererError.BufferCapacityExceeded;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        const new_x1 = x1 / half_window_w - 1.0;
        const new_y1 = 1.0 - y1 / half_window_h;

        const new_x2 = x2 / half_window_w - 1.0;
        const new_y2 = 1.0 - y2 / half_window_h;

        const new_x3 = x3 / half_window_w - 1.0;
        const new_y3 = 1.0 - y3 / half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x1, new_y1 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x2, new_y2 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x3, new_y3 }, .col = renderer.color };

        renderer.vertices_len += 3;
    }

    pub fn setColor(renderer: *ColoredRenderer, r: f32, g: f32, b: f32, a: f32) void {
        renderer.color[0] = r;
        renderer.color[1] = g;
        renderer.color[2] = b;
        renderer.color[3] = a;
    }
};
