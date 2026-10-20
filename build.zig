const std = @import("std");

pub fn build(b: *std.Build) void {
    const opt = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const mod = b.addModule("fbhc", .{
        .omit_frame_pointer = false,
        .target = target,
        .optimize = opt,
        .link_libc = false,
        .link_libcpp = false,
        .no_builtin = true,
        .single_threaded = true,
        .root_source_file = b.path("src/entry_point.zig"),
    });
    const executable = b.addExecutable(.{
        .root_module = mod,
        .name = "fbhc",
        // .use_lld = false,
        // .use_llvm = false,
        .use_lld = true,
        .use_llvm = true,
    });
    executable.link_data_sections = true;
    executable.link_function_sections = true;
    executable.link_gc_sections = true;
    executable.lto = .full;
    executable.link_z_lazy = false;
    executable.link_z_relro = true;
    b.installArtifact(executable);
}
