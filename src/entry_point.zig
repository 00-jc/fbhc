const std = @import("std");
const cli = @import("cli.zig");
const emit = @import("emit.zig");
const fib = @import("fib.zig");
const repr = @import("repr.zig");
const tokenize = @import("tokenize.zig").tokenize;

fn generate(comptime K: type, allocator: std.mem.Allocator, src: []const u8, w: *std.Io.Writer) !void
{
    var toks = try tokenize(K, allocator, src);
    defer toks.deinit(allocator);
    const nums = toks.nums.items;
    const strings = toks.strings.items;

    const bits_for_hash: usize = if (nums.len <= 1) 0 else std.math.log2_int_ceil(usize, nums.len);

    try emit.prelude(w, K);
    if (try repr.find(K, allocator, nums, bits_for_hash)) |mask| try repr.emitCode(w, K, mask, nums, strings);
    if (fib.find(K, nums, bits_for_hash)) |found| try fib.emitCode(w, K, found, nums, strings);
    try emit.epilogue(w, K);
}

pub fn main(ini: std.process.Init) !void
{
    const allocator = ini.gpa;
    const io = ini.io;

    var arg_it = ini.minimal.args.iterate();
    const opts = try cli.parse(&arg_it);

    var buf: [1024]u8 = @splat(0);
    var writer = std.Io.File.stdout().writer(io, &buf);
    const w = &writer.interface;
    defer w.flush() catch {};

    const file = try std.Io.Dir.cwd().openFile(io, opts.path, .{.mode = .read_only});
    defer file.close(io);

    var map = try file.createMemoryMap(io, .{.len = try file.length(io), .protection = .{ .read = true}});
    defer map.destroy(io);

    if (opts.use128) try generate(u128, allocator, map.memory, w)
    else try generate(u64, allocator, map.memory, w);
}
