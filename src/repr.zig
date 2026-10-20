//! Representative-bits hash: gathers a minimal set of distinguishing bits.

const std = @import("std");
const solve = @import("solve.zig").solve;
const emit = @import("emit.zig");

fn Runs(comptime K: type) type
{
    return struct {
        const S = std.math.Log2Int(K);
        pub const Run = struct { start: usize, mask: K, dest: usize };

        rem: K,
        dest: usize = 0,

        pub fn next(self: *@This()) ?Run
        {
            if (self.rem == 0) return null;
            const start: usize = @ctz(self.rem);
            const end: usize = @ctz(~(self.rem >> @as(S, @intCast(start))));
            const mask = ~@as(K, 0) >> @as(S, @intCast(@bitSizeOf(K) - end));
            const run: Run = .{ .start = start, .mask = mask, .dest = self.dest };
            self.rem &= ~(mask << @as(S, @intCast(start)));
            self.dest += end;
            return run;
        }
    };
}

fn gather(comptime K: type, x: K, bits: K) K
{
    const S = std.math.Log2Int(K);
    var result: K = 0;
    var runs: Runs(K) = .{ .rem = bits };
    while (runs.next()) |r| result |= ((x >> @as(S, @intCast(r.start))) & r.mask) << @as(S, @intCast(r.dest));
    return result;
}

/// Returns the mask of chosen bit positions, or null when the keys do not
/// differ in enough positions for this hash to be worthwhile.
pub fn find(comptime K: type, allocator: std.mem.Allocator, nums: []const K, bits_for_hash: usize) !?K
{
    var _and: K = ~@as(K, 0);
    var _or: K = 0;
    for (nums) |n| { _and &= n; _or |= n; }
    const variants = _and ^ _or;
    if (@popCount(variants) < bits_for_hash) return null;

    var set: K = 0;
    const n = nums.len;
    const pair_diffs = try allocator.alloc(K, (n * (n -| 1)) >> 1);
    defer allocator.free(pair_diffs);

    var w: usize = 0;
    for (nums, 0..) |a, i|
    {
        for (nums[i + 1 ..]) |b|
        {
            pair_diffs[w] = a ^ b;
            w += 1;
        }
    }

    for (pair_diffs) |x|
    {
        if (x == 0) return error.IdenticalKeys;
        if (@popCount(x) == 1) set |= x;
    }

    var len: usize = 0;
    for (pair_diffs) |x|
    {
        if (set & x == 0)
        {
            pair_diffs[len] = x;
            len += 1;
        }
    }

    if (len == 0) return set;

    var max_bits: usize = @max(bits_for_hash, @as(usize, @popCount(set)) + 1);
    while (max_bits <= @popCount(variants)) : (max_bits += 1)
    {
        if (solve(K, pair_diffs[0..len], set, max_bits)) |mask| return mask;
    }
    return set;
}

pub fn emitCode(w: *std.Io.Writer, comptime K: type, mask: K, nums: []const K, strings: []const []const u8) !void
{
    const S = std.math.Log2Int(K);
    const ty = emit.cType(K);

    try emit.functionHeader(w, K, "representative_bits_hash", true);
    try emit.writeConst(w, K, mask, false);
    try w.print(";\n  {s} result = 0;\n\n", .{ty});

    var runs: Runs(K) = .{ .rem = mask };
    while (runs.next()) |r|
    {
        try w.print("  result |= ((input >> {d}) & ", .{r.start});
        try emit.writeConst(w, K, r.mask, false);
        try w.print(") << {d};\n", .{r.dest});
    }
    try w.writeAll("  return result;\n}\n");
    try w.print("static const FBHC_CONSTEXPR uint64_t REPRESENTATIVE_TABLE_SIZE = {d};\n", .{@as(u64, 1) << @as(u6, @intCast(@popCount(mask)))});
    try w.print("static const {s} TABLE_REPR[REPRESENTATIVE_TABLE_SIZE] = {{\n", .{ty});
    for (nums, strings) |x, s|
    {
        try w.print("\t[{d:<3}] = ", .{@as(u64, @intCast(gather(K, x, mask)))});
        try emit.writeConst(w, K, x, true);
        try w.print(", // {s}\n", .{s});
    }
    try w.writeAll("};\n");
    _ = S;
}
