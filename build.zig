const std = @import("std");
const mach = @import("libs/mach/build.zig");

pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardOptimizeOption(.{});

    const options = mach.Options{ .core = .{
        .gpu_dawn_options = .{
            .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
            .debug = b.option(bool, "dawn-debug", "Use a debug build of Dawn") orelse false,
        },
    } };

    const app = try mach.App.init(
        b,
        .{
            .name = "Khichdi2D",
            .src = "src/main.zig",
            .target = target,
            .optimize = mode,
            .deps = &[_]std.Build.ModuleDependency{std.Build.ModuleDependency{
                .name = "zigimg",
                .module = b.createModule(.{ .source_file = .{ .path = "libs/zigimg/zigimg.zig" } }),
            }},
            // .res_dirs = if (example.has_assets) &.{example.name ++ "/assets"} else null,
            // .watch_paths = &.{path_suffix ++ example.name},
            // .use_freetype = if (example.use_freetype) "freetype" else null,
            // .use_model3d = example.use_model3d,
        },
    );
    try app.link(options);
    // app.addPackagePath("zigimg", "zigimg/zigimg.zig");
    app.install();

    const compile_step = b.step("compile", "Compile the game");
    compile_step.dependOn(&app.getInstallStep().?.step);

    const run_cmd = try app.run();
    run_cmd.dependOn(compile_step);
    const run_step = b.step("run", "Run the game");
    run_step.dependOn(run_cmd);
}
