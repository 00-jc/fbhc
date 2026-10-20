//! Fibonacci (multiplicative) perfect hash.

const std = @import("std");
const emit = @import("emit.zig");

pub fn Found(comptime K: type) type
{
    return struct { magic: K, shift: std.math.Log2Int(K) };
}

pub fn find(comptime K: type, nums: []const K, bits_for_hash: usize) ?Found(K)
{
    const S = std.math.Log2Int(K);
    const total_bits = @bitSizeOf(K);
    const max_hash_bits = @bitSizeOf(S);

    var random = std.Random.DefaultPrng.init(0x9E3779B185EBCA87);
    var hash_bits: usize = @max(bits_for_hash, 1);

    while (hash_bits <= max_hash_bits) : (hash_bits += 1)
    {
        const shift: S = @intCast(total_bits - hash_bits);
        var tries: u32 = 0;
        while (tries < 1 << 26) : (tries += 1)
        {
            const magic = random.random().int(K) | 1;
            var used: K = 0;
            var collided = false;
            for (nums) |key|
            {
                const slot: S = @intCast((key *% magic) >> shift);
                const slot_bit = @as(K, 1) << slot;
                if (used & slot_bit != 0)
                {
                    collided = true;
                    break;
                }
                used |= slot_bit;
            }
            if (!collided) return .{ .magic = magic, .shift = shift };
        }
    }
    return null;
}

pub fn emitCode(w: *std.Io.Writer, comptime K: type, found: Found(K), nums: []const K, strings: []const []const u8) !void
{
    try w.print("static const {s} TABLE_FIB[] = {{\n", .{emit.cType(K)});
    for (nums, strings) |n, s|
    {
        try w.print("\t[{d:<3}] = ", .{@as(u64, @intCast((n *% found.magic) >> found.shift))});
        try emit.writeConst(w, K, n, true);
        try w.print(", // {s}\n", .{s});
    }
    try w.writeAll("};\n");

    try emit.functionHeader(w, K, "fib_hash", true);
    try w.writeAll("{\n  return ((input * ");
    try emit.writeConst(w, K, found.magic, false);
    try w.print(") >> {d});\n}}\n", .{found.shift});
}
