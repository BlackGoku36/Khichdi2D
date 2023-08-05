const std = @import("std");
const core = @import("core");
const zigimg = @import("zigimg");
const gpu = core.gpu;

const RendererError = error{
    BufferCapacityExceeded,
};

pub fn catchRendererError(renderer_error: RendererError) void {
    switch (renderer_error) {
        error.BufferCapacityExceeded => std.debug.panic("Vertex Buffer capacity exceeded. You may want to increase max_images/max_colored.", .{}),
    }
}

const State = enum { colored, image };

const max_colored: u32 = 4000;
const max_vertices_colored: u32 = max_colored * 4;
const max_indices_colored: u32 = max_colored * 6;
const max_images: u32 = 4000;
const max_vertices_images: u32 = max_images * 4;
const max_indices_images: u32 = max_images * 6;

pub const Renderer = struct {
    image_renderer: ImageRenderer,
    colored_renderer: ColoredRenderer,
    command_encoder: *gpu.CommandEncoder = undefined,
    pass: *gpu.RenderPassEncoder = undefined,
    back_buffer_view: *gpu.TextureView = undefined,
    state: State = .colored,
    re_draw: bool = false,
    debug_timer: core.Timer,
    debug_draw_image: u32 = 0,
    debug_draw_colored: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, image: zigimg.Image) !Renderer {
        var debug_timer = try core.Timer.start();

        var image_renderer = try ImageRenderer.init(allocator, image);
        var colored_renderer = try ColoredRenderer.init(allocator);

        std.log.info("Renderer init time: {d} ms", .{@as(f32, @floatFromInt(debug_timer.lapPrecise())) / @as(f32, @floatFromInt(std.time.ns_per_ms))});

        return Renderer{.image_renderer = image_renderer, .colored_renderer = colored_renderer, .debug_timer = debug_timer };
    }

    pub fn begin(renderer: *Renderer) void {
        _ = renderer.debug_timer.reset();

        renderer.image_renderer.re_draw = renderer.re_draw;
        renderer.colored_renderer.re_draw = renderer.re_draw;

        renderer.back_buffer_view = core.swap_chain.getCurrentTextureView().?;
        const color_attachment = gpu.RenderPassColorAttachment{
            .view = renderer.back_buffer_view,
            .clear_value = std.mem.zeroes(gpu.Color),
            .load_op = .clear,
            .store_op = .store,
        };
        renderer.command_encoder = core.device.createCommandEncoder(null);
        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });
        renderer.pass = renderer.command_encoder.beginRenderPass(&render_pass_info);

        renderer.debug_draw_image = 0;
        renderer.debug_draw_colored = 0;

        if (renderer.re_draw) {
            renderer.image_renderer.resetVertIndexData();
            renderer.colored_renderer.resetVertIndexData();

            const window_size = core.size();
            const half_window_w = @as(f32, @floatFromInt(window_size.width)) * 0.5;
            const half_window_h = @as(f32, @floatFromInt(window_size.height)) * 0.5;
            renderer.image_renderer.half_window_w = half_window_w;
            renderer.image_renderer.half_window_h = half_window_h;
            renderer.colored_renderer.half_window_w = half_window_w;
            renderer.colored_renderer.half_window_h = half_window_h;
        }

        std.log.info("---------------------------", .{});
        std.log.info("Renderer begin time: {d} ms", .{@as(f32, @floatFromInt(renderer.debug_timer.lapPrecise())) / @as(f32, @floatFromInt(std.time.ns_per_ms))});
    }

    fn endImageRenderer(renderer: *Renderer) void {
        if (renderer.image_renderer.vertices.items.len > 0) {
            try renderer.image_renderer.draw(renderer.pass);
            renderer.debug_draw_image += 1;
        }
        renderer.state = .colored;
    }

    fn endColoredRenderer(renderer: *Renderer) void {
        if (renderer.colored_renderer.vertices.items.len > 0) {
            try renderer.colored_renderer.draw(renderer.pass);
            renderer.debug_draw_colored += 1;
        }
        renderer.state = .image;
    }

    pub fn end(renderer: *Renderer) void {
        std.log.info("Renderer paint time: {d} ms", .{@as(f32, @floatFromInt(renderer.debug_timer.lapPrecise())) / @as(f32, @floatFromInt(std.time.ns_per_ms))});

        renderer.endImageRenderer();
        renderer.endColoredRenderer();

        renderer.pass.end();
        renderer.pass.release();

        if (renderer.re_draw) {
            core.queue.writeBuffer(renderer.image_renderer.vertex_buffer, 0, renderer.image_renderer.vertices.items[0..]);
            core.queue.writeBuffer(renderer.colored_renderer.vertex_buffer, 0, renderer.colored_renderer.vertices.items[0..]);
            core.queue.writeBuffer(renderer.colored_renderer.index_buffer, 0, renderer.colored_renderer.indices.items[0..]);
        }

        var gpu_timer = renderer.debug_timer.readPrecise();

        var command = renderer.command_encoder.finish(null);
        renderer.command_encoder.release();
        core.queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        core.swap_chain.present();
        renderer.back_buffer_view.release();

        std.log.info("Renderer gpu time: {d} ms", .{@as(f32, @floatFromInt(renderer.debug_timer.readPrecise() - gpu_timer)) / @as(f32, @floatFromInt(std.time.ns_per_ms))});

        renderer.image_renderer.old_index = 0;
        renderer.image_renderer.index = 0;

        renderer.colored_renderer.old_index = 0;
        renderer.colored_renderer.index = 0;

        renderer.re_draw = false;

        std.log.info("Renderer end time: {d} ms", .{@as(f32, @floatFromInt(renderer.debug_timer.lapPrecise())) / @as(f32, @floatFromInt(std.time.ns_per_ms))});
        std.log.info("Renderer colored vertices: {d}", .{renderer.colored_renderer.vertices.items.len});
        std.log.info("Renderer images vertices: {d}", .{renderer.image_renderer.vertices.items.len});
        std.log.info("Renderer colored draws: {d}", .{renderer.debug_draw_colored});
        std.log.info("Renderer images draws: {d}", .{renderer.debug_draw_image});
    }

    pub fn deinit(renderer: *Renderer) void {
        renderer.image_renderer.deinit();
        renderer.colored_renderer.deinit();
    }

    pub fn drawImage(renderer: *Renderer, x: f32, y: f32) void {
        if (renderer.state == .colored) renderer.endColoredRenderer();
        renderer.image_renderer.drawImage(x, y);
    }

    pub fn drawSubImage(renderer: *Renderer, x: f32, y: f32, x1: f32, y1: f32, width1: f32, height1: f32) void {
        if (renderer.state == .colored) renderer.endColoredRenderer();
        renderer.image_renderer.drawSubImage(x, y, x1, y1, width1, height1);
    }

    pub fn drawScaledImage(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32) void {
        if (renderer.state == .colored) renderer.endColoredRenderer();
        renderer.image_renderer.drawScaledImage(x, y, width, height) catch |err| catchRendererError(err);
    }

    pub inline fn drawScaledSubImage(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32, x1: f32, y1: f32, width1: f32, height1: f32) void {
        if (renderer.state == .colored) renderer.endColoredRenderer();
        renderer.image_renderer.drawScaledSubImage(x, y, width, height, x1, y1, width1, height1);
    }

    pub fn drawRectangle(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32, thiccness: f32) void {
        if (renderer.state == .image) renderer.endImageRenderer();
        renderer.colored_renderer.drawRectangle(x, y, width, height, thiccness);
    }

    pub fn drawFilledRectangle(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32) void {
        if (renderer.state == .image) renderer.endImageRenderer();
        renderer.colored_renderer.drawFilledRectangle(x, y, width, height);
    }

    pub fn drawFilledTriangle(renderer: *Renderer, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        if (renderer.state == .image) renderer.endImageRenderer();
        renderer.colored_renderer.drawFilledTriangle(x1, y1, x2, y2, x3, y3);
    }

    pub fn setColor(renderer: *Renderer, r: f32, g: f32, b: f32, a: f32) void {
        if (!renderer.re_draw) return;
        renderer.colored_renderer.setColor(r, g, b, a);
        renderer.image_renderer.setColor(r, g, b, a);
    }

    pub fn resetColor(renderer: *Renderer) void {
        if (!renderer.re_draw) return;
        renderer.setColor(0.0, 0.0, 0.0, 1.0);
    }
};

pub const ImageVertex = extern struct {
    pos: @Vector(2, f32),
    uv: @Vector(2, f32),
    col: @Vector(4, f32),
};

pub const ImageRenderer = struct {
    pipeline: *gpu.RenderPipeline,
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    vertices: std.ArrayList(ImageVertex),
    indices_len: u32 = 0,
    bind_group: *gpu.BindGroup,
    texture: *gpu.Texture,
    old_index: u32 = 0,
    index: u32 = 0,
    color: [4]f32 = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    re_draw: bool = false,
    half_window_w: f32,
    half_window_h: f32,

    pub fn init(allocator: std.mem.Allocator, image: zigimg.Image) !ImageRenderer {
        const shader_module = core.device.createShaderModuleWGSL("image_shader.wgsl", @embedFile("image_shader.wgsl"));

        const blend = gpu.BlendState{
            .color = .{
                .operation = .add,
                .src_factor = .src_alpha,
                .dst_factor = .one_minus_src_alpha,
            },
        };
        const color_target = gpu.ColorTargetState{ .format = core.descriptor.format, .blend = &blend, .write_mask = gpu.ColorWriteMaskFlags.all };

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

        const vertex_buffer = core.device.createBuffer(&.{
            .label = "image_vertex_buffer",
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = @sizeOf(ImageVertex) * max_vertices_images,
        });

        const index_buffer = core.device.createBuffer(&.{
            .label = "image_index_buffer",
            .usage = .{ .index = true, .copy_dst = true },
            .size = @sizeOf(u32) * max_indices_images,
        });

        var vertices = try std.ArrayList(ImageVertex).initCapacity(allocator, max_vertices_images);

        var indices = try std.ArrayList(u32).initCapacity(allocator, max_indices_images);
        defer indices.deinit();

        var i: u32 = 0;
        var j: u32 = 0;

        while (i < max_indices_images) : (i += 6) {
            indices.appendAssumeCapacity(j);
            indices.appendAssumeCapacity(j + 1);
            indices.appendAssumeCapacity(j + 2);
            indices.appendAssumeCapacity(j + 2);
            indices.appendAssumeCapacity(j + 3);
            indices.appendAssumeCapacity(j);
            j += 4;
        }
        core.queue.writeBuffer(index_buffer, 0, indices.items[0..]);

        const vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vert_main",
            .buffers = &.{vertex_buffer_layout},
        });

        const pipeline_desc = gpu.RenderPipeline.Descriptor{
            .fragment = &fragment,
            .vertex = vertex,
        };

        var pipeline = core.device.createRenderPipeline(&pipeline_desc);

        var img: zigimg.Image = image;

        const img_size = gpu.Extent3D{ .width = @as(u32, @intCast(img.width)), .height = @as(u32, @intCast(img.height)) };
        const texture = core.device.createTexture(&.{
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
            .bytes_per_row = @as(u32, @intCast(img.width * 4)),
            .rows_per_image = @as(u32, @intCast(img.height)),
        };

        const sampler = core.device.createSampler(&.{
            .mag_filter = .linear,
            .min_filter = .linear,
        });

        switch (img.pixels) {
            .rgba32 => |pixels| core.queue.writeTexture(&.{ .texture = texture }, &texture_data_layout, &img_size, pixels),
            .rgb24 => |pixels| {
                const data = try rgb24ToRgba32(allocator, pixels);
                defer data.deinit(allocator);
                core.queue.writeTexture(&.{ .texture = texture }, &texture_data_layout, &img_size, data.rgba32);
            },
            else => @panic("unsupported image color format"),
        }

        const bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = pipeline.getBindGroupLayout(0), .entries = &.{ gpu.BindGroup.Entry.sampler(0, sampler), gpu.BindGroup.Entry.textureView(1, texture.createView(&gpu.TextureView.Descriptor{})) } }));

        shader_module.release();

        const window_size = core.size();
        const half_window_w = @as(f32, @floatFromInt(window_size.width)) * 0.5;
        const half_window_h = @as(f32, @floatFromInt(window_size.height)) * 0.5;

        return ImageRenderer{
            .pipeline = pipeline,
            .vertices = vertices,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .bind_group = bind_group,
            .texture = texture,
            .half_window_w = half_window_w,
            .half_window_h = half_window_h,
        };
    }

    pub fn deinit(renderer: *ImageRenderer) void {
        renderer.vertices.deinit();
        renderer.vertex_buffer.release();
        renderer.index_buffer.release();
        renderer.bind_group.release();
    }

    pub fn draw(renderer: *ImageRenderer, pass: *gpu.RenderPassEncoder) !void {
        pass.setPipeline(renderer.pipeline);
        pass.setVertexBuffer(0, renderer.vertex_buffer, 0, @sizeOf(ImageVertex) * renderer.vertices.items.len);
        pass.setIndexBuffer(renderer.index_buffer, .uint32, 0, @sizeOf(u32) * renderer.indices_len);
        pass.setBindGroup(0, renderer.bind_group, &.{});
        pass.drawIndexed(renderer.index - renderer.old_index, 1, renderer.old_index, 0, 0);

        renderer.old_index = renderer.index;
    }

    pub fn drawImage(renderer: *ImageRenderer, x: f32, y: f32) !void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        std.debug.assert(renderer.vertices.items.len <= max_vertices_images);

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = @as(f32, @floatFromInt(renderer.texture.getWidth())) / renderer.half_window_w;
        const new_height = @as(f32, @floatFromInt(renderer.texture.getHeight())) / renderer.half_window_h;

        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y }, .uv = .{ 1.0, 0.0 }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y }, .uv = .{ 0.0, 0.0 }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y - new_height }, .uv = .{ 0.0, 1.0 }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ 1.0, 1.0 }, .col = renderer.color });

        renderer.indices_len += 6;
    }

    pub fn drawSubImage(renderer: *ImageRenderer, x: f32, y: f32, x1: f32, y1: f32, width1: f32, height1: f32) !void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        std.debug.assert(renderer.vertices.items.len <= max_vertices_images);

        const tex_width: f32 = @as(f32, @floatFromInt(renderer.texture.getWidth()));
        const tex_height: f32 = @as(f32, @floatFromInt(renderer.texture.getHeight()));

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = tex_width / renderer.half_window_w;
        const new_height = tex_height / renderer.half_window_h;

        const sub_x = x1 / tex_width;
        const sub_y = y1 / tex_height;
        const sub_width = width1 / tex_width;
        const sub_height = height1 / tex_height;

        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y }, .uv = .{ sub_x + sub_width, sub_y }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y }, .uv = .{ sub_x, sub_y }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y - new_height }, .uv = .{ sub_x, sub_y + sub_height }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ sub_x + sub_width, sub_y + sub_height }, .col = renderer.color });

        renderer.indices_len += 6;
    }

    pub fn drawScaledImage(renderer: *ImageRenderer, x: f32, y: f32, width: f32, height: f32) !void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        if (renderer.vertices.items.len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = width / renderer.half_window_w;
        const new_height = height / renderer.half_window_h;

        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y }, .uv = .{ 1.0, 0.0 }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y }, .uv = .{ 0.0, 0.0 }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y - new_height }, .uv = .{ 0.0, 1.0 }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ 1.0, 1.0 }, .col = renderer.color });

        renderer.indices_len += 6;
    }

    pub fn drawScaledSubImage(renderer: *ImageRenderer, x: f32, y: f32, width: f32, height: f32, x1: f32, y1: f32, width1: f32, height1: f32) void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        if (renderer.vertices.items.len >= max_vertices_images) return RendererError.BufferCapacityExceeded;

        const tex_width: f32 = @as(f32, @floatFromInt(renderer.texture.getWidth()));
        const tex_height: f32 = @as(f32, @floatFromInt(renderer.texture.getHeight()));

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = width / renderer.half_window_w;
        const new_height = height / renderer.half_window_h;

        const sub_x = x1 / tex_width;
        const sub_y = y1 / tex_height;
        const sub_width = width1 / tex_width;
        const sub_height = height1 / tex_height;

        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y }, .uv = .{ sub_x + sub_width, sub_y }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y }, .uv = .{ sub_x, sub_y }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y - new_height }, .uv = .{ sub_x, sub_y + sub_height }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y - new_height }, .uv = .{ sub_x + sub_width, sub_y + sub_height }, .col = renderer.color });

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

    pub fn resetVertIndexData(renderer: *ImageRenderer) void {
        renderer.vertices.shrinkRetainingCapacity(0);
        renderer.indices_len = 0;
    }
};

pub const ColorVertex = extern struct {
    pos: @Vector(2, f32),
    col: @Vector(4, f32),
};

pub const ColoredRenderer = struct {
    pipeline: *gpu.RenderPipeline,
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    vertices: std.ArrayList(ColorVertex),
    indices: std.ArrayList(u32),
    color: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    old_index: u32 = 0,
    index: u32 = 0,
    re_draw: bool = false,
    half_window_w: f32,
    half_window_h: f32,

    pub fn init(allocator: std.mem.Allocator) !ColoredRenderer {
        const shader_module = core.device.createShaderModuleWGSL("color_shader.wgsl", @embedFile("color_shader.wgsl"));

        const blend = gpu.BlendState{
            .color = .{
                .operation = .add,
                .src_factor = .src_alpha,
                .dst_factor = .one_minus_src_alpha,
            },
        };

        const color_target = gpu.ColorTargetState{ .format = core.descriptor.format, .blend = &blend, .write_mask = gpu.ColorWriteMaskFlags.all };

        const fragment = gpu.FragmentState.init(.{ .module = shader_module, .entry_point = "frag_main", .targets = &.{color_target} });

        var vertices = try std.ArrayList(ColorVertex).initCapacity(allocator, max_vertices_colored);
        var indices = try std.ArrayList(u32).initCapacity(allocator, max_indices_colored);

        const vertex_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x2, .offset = @offsetOf(ColorVertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x4, .offset = @offsetOf(ColorVertex, "col"), .shader_location = 1 },
        };

        const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(ColorVertex),
            .step_mode = .vertex,
            .attributes = &vertex_attributes,
        });

        const vertex_buffer = core.device.createBuffer(&.{
            .label = "colored_vertex_buffer",
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = @sizeOf(ColorVertex) * max_vertices_colored,
        });

        const index_buffer = core.device.createBuffer(&.{
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

        var pipeline = core.device.createRenderPipeline(&pipeline_desc);

        shader_module.release();

        const window_size = core.size();
        const half_window_w = @as(f32, @floatFromInt(window_size.width)) * 0.5;
        const half_window_h = @as(f32, @floatFromInt(window_size.height)) * 0.5;

        return ColoredRenderer{
            .pipeline = pipeline,
            .vertices = vertices,
            .indices = indices,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .half_window_w = half_window_w,
            .half_window_h = half_window_h,
        };
    }

    pub fn deinit(renderer: *ColoredRenderer) void {
        renderer.vertices.deinit();
        renderer.indices.deinit();
        renderer.vertex_buffer.release();
        renderer.index_buffer.release();
    }

    pub fn draw(renderer: *ColoredRenderer, pass: *gpu.RenderPassEncoder) !void {
        pass.setPipeline(renderer.pipeline);
        pass.setVertexBuffer(0, renderer.vertex_buffer, 0, @sizeOf(ColorVertex) * renderer.vertices.items.len);
        pass.setIndexBuffer(renderer.index_buffer, .uint32, 0, @sizeOf(u32) * renderer.indices.items.len);
        pass.drawIndexed(renderer.index - renderer.old_index, 1, renderer.old_index, 0, 0);

        renderer.old_index = renderer.index;
    }

    pub fn drawRectangle(renderer: *ColoredRenderer, x: f32, y: f32, width: f32, height: f32, thiccness: f32) void {
        const half_thicc: f32 = thiccness / 2.0;
        renderer.drawFilledRectangle(x - half_thicc, y - half_thicc, width + thiccness, thiccness);
        renderer.drawFilledRectangle(x + width - half_thicc, y - half_thicc, thiccness, height + thiccness);
        renderer.drawFilledRectangle(x - half_thicc, y + height - half_thicc, width + thiccness, thiccness);
        renderer.drawFilledRectangle(x - half_thicc, y - half_thicc, thiccness, height + thiccness);
    }

    pub fn drawFilledRectangle(renderer: *ColoredRenderer, x: f32, y: f32, width: f32, height: f32) void {
        renderer.index += 6;
        if (!renderer.re_draw) return;

        std.debug.assert(renderer.vertices.items.len <= max_vertices_colored);

        const new_x = x / renderer.half_window_w - 1.0;
        const new_y = 1.0 - y / renderer.half_window_h;
        const new_width = width / renderer.half_window_w;
        const new_height = height / renderer.half_window_h;

        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x, new_y - new_height }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x + new_width, new_y - new_height }, .col = renderer.color });

        const vert_len = @as(u32, @intCast(renderer.vertices.items.len));
        renderer.indices.appendAssumeCapacity(vert_len - 4);
        renderer.indices.appendAssumeCapacity(vert_len - 4 + 1);
        renderer.indices.appendAssumeCapacity(vert_len - 4 + 2);
        renderer.indices.appendAssumeCapacity(vert_len - 4 + 2);
        renderer.indices.appendAssumeCapacity(vert_len - 4 + 3);
        renderer.indices.appendAssumeCapacity(vert_len - 4);
    }

    pub fn drawFilledTriangle(renderer: *ColoredRenderer, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        renderer.index += 3;
        if (!renderer.re_draw) return;

        std.debug.assert(renderer.vertices.items.len <= max_vertices_colored);

        const new_x1 = x1 / renderer.half_window_w - 1.0;
        const new_y1 = 1.0 - y1 / renderer.half_window_h;

        const new_x2 = x2 / renderer.half_window_w - 1.0;
        const new_y2 = 1.0 - y2 / renderer.half_window_h;

        const new_x3 = x3 / renderer.half_window_w - 1.0;
        const new_y3 = 1.0 - y3 / renderer.half_window_h;

        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x1, new_y1 }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x2, new_y2 }, .col = renderer.color });
        renderer.vertices.appendAssumeCapacity(.{ .pos = .{ new_x3, new_y3 }, .col = renderer.color });

        const vert_len = @as(u32, @intCast(renderer.vertices.items.len));
        renderer.indices.appendAssumeCapacity(vert_len - 3);
        renderer.indices.appendAssumeCapacity(vert_len - 3 + 1);
        renderer.indices.appendAssumeCapacity(vert_len - 3 + 2);
    }

    pub fn setColor(renderer: *ColoredRenderer, r: f32, g: f32, b: f32, a: f32) void {
        renderer.color[0] = r;
        renderer.color[1] = g;
        renderer.color[2] = b;
        renderer.color[3] = a;
    }

    pub fn resetVertIndexData(renderer: *ColoredRenderer) void {
        renderer.vertices.shrinkRetainingCapacity(0);
        renderer.indices.shrinkRetainingCapacity(0);
    }
};
