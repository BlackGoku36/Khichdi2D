const std = @import("std");
const mach = @import("mach");
const zigimg = @import("zigimg");
const gpu = mach.gpu;

const raw_img = @embedFile("mach.png");

const RendererError = error{
    BufferCapacityExceeded,
};

const State = enum { colored, image };

const max_colored: u32 = 4000;
const max_vertices_colored: u32 = max_colored * 4;
const max_indices_colored: u32 = max_colored * 6;
const max_images: u32 = 4000;
const max_vertices_images: u32 = max_images * 4;
const max_indices_images: u32 = max_images * 6;

pub const Renderer = struct {
    core: *mach.Core,
    queue: *gpu.Queue,
    image_renderer: ImageRenderer,
    colored_renderer: ColoredRenderer,
    command_encoder: *gpu.CommandEncoder = undefined,
    pass: *gpu.RenderPassEncoder = undefined,
    back_buffer_view: *gpu.TextureView = undefined,
    state: State = .colored,
    re_draw: bool = false,

    pub fn init(core: *mach.Core, allocator: std.mem.Allocator) !Renderer {
        var queue = core.device().getQueue();
        var image_renderer = try ImageRenderer.init(core, queue, allocator);
        var colored_renderer = ColoredRenderer.init(core, queue);

        return Renderer{ .core = core, .queue = queue, .image_renderer = image_renderer, .colored_renderer = colored_renderer };
    }

    pub fn begin(renderer: *Renderer) void {
        renderer.image_renderer.re_draw = renderer.re_draw;
        renderer.colored_renderer.re_draw = renderer.re_draw;

        renderer.back_buffer_view = renderer.core.swapChain().getCurrentTextureView();
        const color_attachment = gpu.RenderPassColorAttachment{
            .view = renderer.back_buffer_view,
            .clear_value = std.mem.zeroes(gpu.Color),
            .load_op = .clear,
            .store_op = .store,
        };
        renderer.command_encoder = renderer.core.device().createCommandEncoder(null);
        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });
        renderer.pass = renderer.command_encoder.beginRenderPass(&render_pass_info);

        if (!renderer.re_draw) return;
        renderer.image_renderer.vertices_len = 0;
        renderer.image_renderer.indices_len = 0;
        renderer.colored_renderer.vertices_len = 0;
        renderer.colored_renderer.indices_len = 0;

        const window_size = renderer.core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;
        renderer.image_renderer.half_window_w = half_window_w;
        renderer.image_renderer.half_window_h = half_window_h;
        renderer.colored_renderer.half_window_w = half_window_w;
        renderer.colored_renderer.half_window_h = half_window_h;
    }

    fn endImageRenderer(renderer: *Renderer) void {
        if (renderer.image_renderer.vertices_len > 0) try renderer.image_renderer.draw(renderer.pass);
        renderer.state = .colored;
    }

    fn endColoredRenderer(renderer: *Renderer) void {
        if (renderer.colored_renderer.vertices_len > 0) try renderer.colored_renderer.draw(renderer.pass);
        renderer.state = .image;
    }

    pub fn end(renderer: *Renderer) void {
        renderer.endImageRenderer();
        renderer.endColoredRenderer();

        renderer.pass.end();
        renderer.pass.release();

        if (renderer.re_draw) {
            renderer.queue.writeBuffer(renderer.image_renderer.vertex_buffer, 0, renderer.image_renderer.vertices[0..]);
            renderer.queue.writeBuffer(renderer.colored_renderer.vertex_buffer, 0, renderer.colored_renderer.vertices[0..]);
            renderer.queue.writeBuffer(renderer.colored_renderer.index_buffer, 0, renderer.colored_renderer.indices[0..]);
        }

        var command = renderer.command_encoder.finish(null);
        renderer.command_encoder.release();
        renderer.queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        renderer.core.swapChain().present();
        renderer.back_buffer_view.release();

        renderer.image_renderer.old_index = 0;
        renderer.image_renderer.index = 0;

        renderer.colored_renderer.old_index = 0;
        renderer.colored_renderer.index = 0;

        renderer.re_draw = false;
    }

    pub fn deinit(renderer: *Renderer) void {
        renderer.image_renderer.deinit();
        renderer.colored_renderer.deinit();
    }

    pub fn drawImage(renderer: *Renderer, x: f32, y: f32) !void {
        if (renderer.state == .colored) renderer.endColoredRenderer();
        try renderer.image_renderer.drawImage(x, y);
    }

    pub fn drawSubImage(renderer: *Renderer, x: f32, y: f32, x1: f32, y1: f32, width1: f32, height1: f32) !void {
        if (renderer.state == .colored) renderer.endColoredRenderer();
        try renderer.image_renderer.drawSubImage(x, y, x1, y1, width1, height1);
    }

    pub fn drawScaledImage(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32) !void {
        if (renderer.state == .colored) renderer.endColoredRenderer();
        try renderer.image_renderer.drawScaledImage(x, y, width, height);
    }

    pub inline fn drawScaledSubImage(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32, x1: f32, y1: f32, width1: f32, height1: f32) !void {
        if (renderer.state == .colored) renderer.endColoredRenderer();
        try renderer.image_renderer.drawScaledSubImage(x, y, width, height, x1, y1, width1, height1);
    }

    pub fn drawRectangle(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32, thiccness: f32) !void {
        if (renderer.state == .image) renderer.endImageRenderer();
        try renderer.colored_renderer.drawRectangle(x, y, width, height, thiccness);
    }

    pub fn drawFilledRectangle(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32) !void {
        if (renderer.state == .image) renderer.endImageRenderer();
        try renderer.colored_renderer.drawFilledRectangle(x, y, width, height);
    }

    pub fn drawFilledTriangle(renderer: *Renderer, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) !void {
        if (renderer.state == .image) renderer.endImageRenderer();
        try renderer.colored_renderer.drawFilledTriangle(x1, y1, x2, y2, x3, y3);
    }

    pub fn setColor(renderer: *Renderer, r: f32, g: f32, b: f32, a: f32) void {
        if (!renderer.re_draw) return;
        renderer.colored_renderer.setColor(r, g, b, a);
        renderer.image_renderer.setColor(r, g, b, a);
    }
};

pub const ImageVertex = extern struct {
    pos: @Vector(2, f32),
    uv: @Vector(2, f32),
    col: @Vector(4, f32),
};

pub const ImageRenderer = struct {
    core: *mach.Core,
    pipeline: *gpu.RenderPipeline,
    queue: *gpu.Queue,
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    vertices: [max_vertices_images]ImageVertex = undefined,
    vertices_len: u32 = 0,
    indices_len: u32 = 0,
    bind_group: *gpu.BindGroup,
    texture: *gpu.Texture,
    old_index: u32 = 0,
    index: u32 = 0,
    color: [4]f32 = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    re_draw: bool = false,
    half_window_w: f32,
    half_window_h: f32,

    pub fn init(core: *mach.Core, queue: *gpu.Queue, allocator: std.mem.Allocator) !ImageRenderer {
        const shader_module = core.device().createShaderModuleWGSL("image_shader.wgsl", @embedFile("image_shader.wgsl"));

        const blend = gpu.BlendState{
            .color = .{
                .operation = .add,
                .src_factor = .src_alpha,
                .dst_factor = .one_minus_src_alpha,
            },
        };
        const color_target = gpu.ColorTargetState{ .format = core.descriptor().format, .blend = &blend, .write_mask = gpu.ColorWriteMaskFlags.all };

        const fragment = gpu.FragmentState.init(.{ .module = shader_module, .entry_point = "frag_main", .targets = &.{color_target} });

        const vertex_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x2, .offset = @offsetOf(ImageVertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x2, .offset = @offsetOf(ImageVertex, "uv"), .shader_location = 1 },
            .{ .format = .float32x4, .offset = @offsetOf(ImageVertex, "col"), .shader_location = 2 },
        };

        const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(ImageVertex),
            .step_mode = .vertex,
            .attributes = &vertex_attributes,
        });

        const vertex_buffer = core.device().createBuffer(&.{
            .label = "image_vertex_buffer",
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = @sizeOf(ImageVertex) * max_vertices_images,
        });

        const index_buffer = core.device().createBuffer(&.{
            .label = "image_index_buffer",
            .usage = .{ .index = true, .copy_dst = true },
            .size = @sizeOf(u32) * max_indices_images,
        });

        var indices: [max_indices_images]u32 = undefined;

        var i: u32 = 0;
        var j: u32 = 0;

        while (i < max_indices_images) : (i += 6) {
            indices[i + 0] = j + 0;
            indices[i + 1] = j + 1;
            indices[i + 2] = j + 2;
            indices[i + 3] = j + 2;
            indices[i + 4] = j + 3;
            indices[i + 5] = j + 0;
            j += 4;
        }
        queue.writeBuffer(index_buffer, 0, indices[0..]);

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

        var img = try zigimg.Image.fromMemory(allocator, raw_img);
        defer img.deinit();

        const img_size = gpu.Extent3D{ .width = @intCast(u32, img.width), .height = @intCast(u32, img.height) };
        const texture = core.device().createTexture(&.{
            .label = "mach_texture",
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

        const window_size = core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;

        return ImageRenderer{
            .core = core,
            .pipeline = pipeline,
            .queue = queue,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .bind_group = bind_group,
            .texture = texture,
            .half_window_w = half_window_w,
            .half_window_h = half_window_h,
        };
    }

    pub fn deinit(renderer: *ImageRenderer) void {
        renderer.vertex_buffer.release();
        renderer.index_buffer.release();
        renderer.bind_group.release();
    }

    pub fn draw(renderer: *ImageRenderer, pass: *gpu.RenderPassEncoder) !void {
        pass.setPipeline(renderer.pipeline);
        pass.setVertexBuffer(0, renderer.vertex_buffer, 0, @sizeOf(ImageVertex) * renderer.vertices_len);
        pass.setIndexBuffer(renderer.index_buffer, .uint32, 0, @sizeOf(u32) * renderer.indices_len);
        pass.setBindGroup(0, renderer.bind_group, &.{});
        pass.drawIndexed(renderer.index - renderer.old_index, 1, renderer.old_index, 0, 0);

        renderer.old_index = renderer.index;
    }

    pub fn drawImage(renderer: *ImageRenderer, x: f32, y: f32) !void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        if (renderer.vertices_len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = @intToFloat(f32, renderer.texture.getWidth()) / renderer.half_window_w;
        const new_height = @intToFloat(f32, renderer.texture.getHeight()) / renderer.half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ 1.0, 0.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .uv = .{ 0.0, 0.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ 0.0, 1.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ 1.0, 1.0 }, .col = renderer.color };

        renderer.vertices_len += 4;
        renderer.indices_len += 6;
    }

    pub fn drawSubImage(renderer: *ImageRenderer, x: f32, y: f32, x1: f32, y1: f32, width1: f32, height1: f32) !void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        if (renderer.vertices_len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = @intToFloat(f32, renderer.texture.getWidth()) / renderer.half_window_w;
        const new_height = @intToFloat(f32, renderer.texture.getHeight()) / renderer.half_window_h;

        const sub_x = x1 / @intToFloat(f32, renderer.texture.getWidth());
        const sub_y = y1 / @intToFloat(f32, renderer.texture.getHeight());
        const sub_width = width1 / @intToFloat(f32, renderer.texture.getWidth());
        const sub_height = height1 / @intToFloat(f32, renderer.texture.getHeight());

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ sub_x + sub_width, sub_y }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .uv = .{ sub_x, sub_y }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ sub_x, sub_y + sub_height }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ sub_x + sub_width, sub_y + sub_height }, .col = renderer.color };

        renderer.vertices_len += 4;
        renderer.indices_len += 6;
    }

    pub fn drawScaledImage(renderer: *ImageRenderer, x: f32, y: f32, width: f32, height: f32) !void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        if (renderer.vertices_len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = width / renderer.half_window_w;
        const new_height = height / renderer.half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ 1.0, 0.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .uv = .{ 0.0, 0.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ 0.0, 1.0 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ 1.0, 1.0 }, .col = renderer.color };

        renderer.vertices_len += 4;
        renderer.indices_len += 6;
    }

    pub fn drawScaledSubImage(renderer: *ImageRenderer, x: f32, y: f32, width: f32, height: f32, x1: f32, y1: f32, width1: f32, height1: f32) !void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        if (renderer.vertices_len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = width / renderer.half_window_w;
        const new_height = height / renderer.half_window_h;

        const sub_x = x1 / @intToFloat(f32, renderer.texture.getWidth());
        const sub_y = y1 / @intToFloat(f32, renderer.texture.getHeight());
        const sub_width = width1 / @intToFloat(f32, renderer.texture.getWidth());
        const sub_height = height1 / @intToFloat(f32, renderer.texture.getHeight());

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .uv = .{ sub_x + sub_width, sub_y }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .uv = .{ sub_x, sub_y }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .uv = .{ sub_x, sub_y + sub_height }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ sub_x + sub_width, sub_y + sub_height }, .col = renderer.color };

        renderer.vertices_len += 4;
        renderer.indices_len += 6;
    }

    fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
        const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
        var i: usize = 0;
        while (i < in.len) : (i += 1) {
            out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
        }
        return out;
    }

    pub fn setColor(renderer: *ImageRenderer, r: f32, g: f32, b: f32, a: f32) void {
        renderer.color[0] = r;
        renderer.color[1] = g;
        renderer.color[2] = b;
        renderer.color[3] = a;
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
    index_buffer: *gpu.Buffer,
    vertices: [max_vertices_colored]ColorVertex = undefined,
    indices: [max_indices_colored]u32 = undefined,
    vertices_len: u32 = 0,
    indices_len: u32 = 0,
    color: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    old_index: u32 = 0,
    index: u32 = 0,
    re_draw: bool = false,
    half_window_w: f32,
    half_window_h: f32,

    pub fn init(core: *mach.Core, queue: *gpu.Queue) ColoredRenderer {
        const shader_module = core.device().createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));

        const blend = gpu.BlendState{
            .color = .{
                .operation = .add,
                .src_factor = .src_alpha,
                .dst_factor = .one_minus_src_alpha,
            },
        };

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
            .label = "colored_vertex_buffer",
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = @sizeOf(ColorVertex) * max_vertices_colored,
        });

        const index_buffer = core.device().createBuffer(&.{
            .label = "colored_index_buffer",
            .usage = .{ .index = true, .copy_dst = true },
            .size = @sizeOf(u32) * max_indices_colored,
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

        shader_module.release();

        const window_size = core.size();
        const half_window_w = @intToFloat(f32, window_size.width) * 0.5;
        const half_window_h = @intToFloat(f32, window_size.height) * 0.5;

        return ColoredRenderer{
            .core = core,
            .pipeline = pipeline,
            .queue = queue,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .half_window_w = half_window_w,
            .half_window_h = half_window_h,
        };
    }

    pub fn deinit(renderer: *ColoredRenderer) void {
        renderer.vertex_buffer.release();
        renderer.index_buffer.release();
    }

    pub fn draw(renderer: *ColoredRenderer, pass: *gpu.RenderPassEncoder) !void {
        pass.setPipeline(renderer.pipeline);
        pass.setVertexBuffer(0, renderer.vertex_buffer, 0, @sizeOf(ColorVertex) * renderer.vertices_len);
        pass.setIndexBuffer(renderer.index_buffer, .uint32, 0, @sizeOf(u32) * renderer.indices_len);
        pass.drawIndexed(renderer.index - renderer.old_index, 1, renderer.old_index, 0, 0);

        renderer.old_index = renderer.index;
    }

    pub fn drawRectangle(renderer: *ColoredRenderer, x: f32, y: f32, width: f32, height: f32, thiccness: f32) !void {
        const half_thicc: f32 = thiccness / 2.0;
        try renderer.drawFilledRectangle(x - half_thicc, y - half_thicc, width + thiccness, thiccness);
        try renderer.drawFilledRectangle(x + width - half_thicc, y - half_thicc, thiccness, height + thiccness);
        try renderer.drawFilledRectangle(x - half_thicc, y + height - half_thicc, width + thiccness, thiccness);
        try renderer.drawFilledRectangle(x - half_thicc, y - half_thicc, thiccness, height + thiccness);
    }

    pub fn drawFilledRectangle(renderer: *ColoredRenderer, x: f32, y: f32, width: f32, height: f32) !void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        if (renderer.vertices_len >= max_vertices_colored) return RendererError.BufferCapacityExceeded;

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = width / renderer.half_window_w;
        const new_height = height / renderer.half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x + new_width, new_y }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x, new_y }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x, new_y - new_height }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 3] = .{ .pos = .{ new_x + new_width, new_y - new_height }, .col = renderer.color };

        renderer.indices[renderer.indices_len + 0] = renderer.vertices_len + 0;
        renderer.indices[renderer.indices_len + 1] = renderer.vertices_len + 1;
        renderer.indices[renderer.indices_len + 2] = renderer.vertices_len + 2;
        renderer.indices[renderer.indices_len + 3] = renderer.vertices_len + 2;
        renderer.indices[renderer.indices_len + 4] = renderer.vertices_len + 3;
        renderer.indices[renderer.indices_len + 5] = renderer.vertices_len + 0;

        renderer.vertices_len += 4;
        renderer.indices_len += 6;
    }

    pub fn drawFilledTriangle(renderer: *ColoredRenderer, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) !void {
        renderer.index += 3;
        if (!renderer.re_draw) return;

        if (renderer.vertices_len >= max_vertices_colored) return RendererError.BufferCapacityExceeded;

        const new_x1 = x1 / renderer.half_window_w - 1.0;
        const new_y1 = 1.0 - y1 / renderer.half_window_h;

        const new_x2 = x2 / renderer.half_window_w - 1.0;
        const new_y2 = 1.0 - y2 / renderer.half_window_h;

        const new_x3 = x3 / renderer.half_window_w - 1.0;
        const new_y3 = 1.0 - y3 / renderer.half_window_h;

        renderer.vertices[renderer.vertices_len + 0] = .{ .pos = .{ new_x1, new_y1 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 1] = .{ .pos = .{ new_x2, new_y2 }, .col = renderer.color };
        renderer.vertices[renderer.vertices_len + 2] = .{ .pos = .{ new_x3, new_y3 }, .col = renderer.color };

        renderer.indices[renderer.indices_len + 0] = renderer.vertices_len + 0;
        renderer.indices[renderer.indices_len + 1] = renderer.vertices_len + 1;
        renderer.indices[renderer.indices_len + 2] = renderer.vertices_len + 2;

        renderer.vertices_len += 3;
        renderer.indices_len += 3;
    }

    pub fn setColor(renderer: *ColoredRenderer, r: f32, g: f32, b: f32, a: f32) void {
        if (!renderer.re_draw) return;
        renderer.color[0] = r;
        renderer.color[1] = g;
        renderer.color[2] = b;
        renderer.color[3] = a;
    }
};
