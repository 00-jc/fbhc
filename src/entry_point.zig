const std = @import("std");
const solve = @import("solve.zig").solve;

const Vec = @Vector(std.simd.suggestVectorLength(u8).?, u8);
const UnalignedVecPtr = [*]align(1) const Vec;

inline fn pack(tok: []const u8) u64
{
    var buf: [8]u8 = @splat(0);
    @memcpy(buf[0..tok.len], tok);
    return std.mem.readInt(u64, &buf, .little);
}

pub fn main(ini: std.process.Init) !void
{
    const allocator = ini.gpa;
    const io = ini.io;

    var arg_it = ini.minimal.args.iterate();
    _ = arg_it.skip();
    const name_of_file = arg_it.next() orelse return error.NoFileInArgs;

    var buf: [1024]u8 = @splat(0);
    var writer = std.Io.File.stdout().writer(io, &buf);
    var interface = &writer.interface;
    defer interface.flush() catch {};

    const file = try std.Io.Dir.cwd().openFile(io, name_of_file, .{.mode = .read_only});
    defer file.close(io);

    var map = try file.createMemoryMap(io, .{.len = try file.length(io), .protection = .{ .read = true}});
    defer map.destroy(io);

    const src = map.memory;

    const tail_start = src.len - (src.len & (@sizeOf(Vec) - 1));
    var it: usize = 0;
    var safe_buf: [@sizeOf(Vec)]u8 = @splat(' ');
    @memcpy(safe_buf[0 .. src.len - tail_start], src[tail_start..]);

    var nums = try std.ArrayList(u64).initCapacity(allocator, 32);
    defer nums.deinit(allocator);
    var strings = try  std.ArrayList([]const u8).initCapacity(allocator, 32);
    defer strings.deinit(allocator);

    var carry: u1 = 0;
    var tok_start: usize = 0;

    while (it < src.len) : (it += @sizeOf(Vec))
    {
        const vp: UnalignedVecPtr = if (it + @sizeOf(Vec) <= src.len) @as(UnalignedVecPtr, @ptrCast(src.ptr + it)) else @ptrCast(&safe_buf);
        const v: Vec = vp[0];
        const mask = ~@as(@Int(.unsigned, @typeInfo(Vec).vector.len), @bitCast((v == @as(Vec, @splat(' ')))
                | (v == @as(Vec, @splat('\t')))
                | (v == @as(Vec, @splat('\n')))
                | (v == @as(Vec, @splat('\r')))));
        const Mask = @TypeOf(mask);
        const bits = @bitSizeOf(Mask);
        const prev = (mask << 1) | carry;
        const starts = mask & ~prev;
        var ends = ~mask & prev;
        while (ends != 0) : (ends &= ends - 1)
        {
            const e = @ctz(ends);
            const below = starts & ((@as(Mask, 1) << @intCast(e)) -% 1);
            const sel = 0 -% @as(usize, @intFromBool(below != 0));
            const local = (bits - 1) -% @as(usize, @clz(below));
            const s = ((it +% local) & sel) | (tok_start & ~sel);
            if ((it + e) - s > 8) return error.KeyTooLong;
            try strings.append(allocator, src[s .. it + e]);
            try nums.append(allocator, pack(src[s .. it + e]));
        }
        carry = @truncate(mask >> (bits - 1));
        const has = 0 -% @as(usize, @intFromBool(starts != 0));
        const top = (bits - 1) -% @as(usize, @clz(starts));
        tok_start = ((it +% top) & has) | (tok_start & ~has);
    }
    if (carry == 1)
    {
       if (src.len - tok_start > 8) return error.KeyTooLong;
       try strings.append(allocator, src[tok_start..]);
       try nums.append(allocator, pack(src[tok_start..]));
    }
    var _and: u64 = 0xFFFFFFFFFFFFFFFF;
    var _or: u64 = 0;
    for (nums.items) |n| { _and &= n; _or |= n; }
    const variants = _and ^ _or;

    const bits_for_hash = std.math.log2_int_ceil(u64, nums.items.len);

    const fmt_constexpr =
    \\#if (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L) || defined(__cplusplus)
    \\# define FBHC_CONSTEXPR constexpr
    \\#else
    \\# define FBHC_CONSTEXPR
    \\#endif
    ;
    try interface.writeAll(fmt_constexpr ++ "\n");
    if (@popCount(variants) >= bits_for_hash)
    {
        var set: u64 = 0;
        const n = nums.items.len;
        const pair_diffs = try allocator.alloc(u64, (n * (n - 1)) >> 1);
        defer allocator.free(pair_diffs);

        var w: usize = 0;
        for (nums.items, 0..) |a, i|
        {
            for (nums.items[i + 1 ..]) |b|
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

        var write_idx: usize = 0;
        var len: usize = 0;

        for (pair_diffs) |x|
        {
            if (set & x == 0)
            {
                pair_diffs[write_idx] = x;
                write_idx += 1;
                len += 1;
            }
        }

        var final_mask: u64 = set;

        if (len != 0)
        {
            const relevant_indices = pair_diffs[0 .. len];
            const min_bits = bits_for_hash;
            var max_bits: usize = @max(min_bits, @popCount(set) + 1);
            while (max_bits <= @popCount(variants)) : (max_bits += 1)
            {
                if (solve(relevant_indices, set, max_bits)) |mask|
                {
                    final_mask = mask;
                    break;
                }
            }
        }
        const fmt_represent_func =
            \\#ifdef __GNUC__
            \\__attribute__((__always_inline__, const, __flatten__, __unused__))
            \\#endif
            \\#ifdef __cplusplus
            \\constexpr
            \\#endif
            \\static inline uint64_t
            \\representative_bits_hash(uint64_t input)
            \\{{
            \\  static const FBHC_CONSTEXPR uint64_t REPRESENTATIVE_BITS = 0x{X};
            \\  uint64_t result = 0;
            \\
            ;
        try interface.print(fmt_represent_func ++ "\n", .{final_mask});
        var dest: usize = 0;
        var rem = final_mask;
        while (rem != 0)
        {
            const start = @ctz(rem);
            const end = @ctz(~(rem >> @intCast(start)));
            const mask = ~@as(u64, 0) >> @intCast(64 - end);
            try interface.print("  result |= ((input >> {d}) & 0x{X}) << {d};\n", .{ start, mask, dest });
            rem &= ~(mask << @intCast(start));
            dest += end;
        }
        try interface.writeAll("  return result;\n}\n");
        try interface.print("static const FBHC_CONSTEXPR uint64_t REPRESENTATIVE_TABLE_SIZE = {d};\n", .{@as(u64, 1) << @intCast(@popCount(final_mask))});
        const r_table_header = "static const uint64_t TABLE_REPR[REPRESENTATIVE_TABLE_SIZE] = {\n";
        const r_table_closer = "};\n";
        try interface.writeAll(r_table_header);
        for (nums.items, strings.items) |x, s|
        {
            var result: usize = 0;
            rem = final_mask;
            dest = 0;
            while (rem != 0)
            {
                const start = @ctz(rem);
                const end = @ctz(~(rem >> @intCast(start)));
                const mask = ~@as(u64, 0) >> @intCast(64 - end);
                result |= ((x >> @intCast(start)) & mask) << @intCast(dest);
                rem &= ~(mask << @intCast(start));
                dest += end;
            }
            try interface.print("\t[{d:<3}] = 0x{X:0>16}, // {s}\n", .{ result, x, s });
        }
        try interface.writeAll(r_table_closer);
    }

    var random = std.Random.DefaultPrng.init(0x9E3779B185EBCA87);
    var hash_bits: u7 = bits_for_hash;
    var found_magic: ?u64 = null;
    var found_shift: u6 = 0;

    search: while (hash_bits <= 6) : (hash_bits += 1)
    {
        const shift: u6 = @intCast(64 - hash_bits);
        var tries: u32 = 0;
        while (tries < 1 << 26) : (tries += 1)
        {
            const magic = random.next() | 1;
            var used: u64 = 0;
            var collided = false;
            for (nums.items) |key|
            {
                const slot: u6 = @intCast((key *% magic) >> shift);
                const slot_bit = @as(u64, 1) << slot;
                if (used & slot_bit != 0)
                {
                    collided = true;
                    break;
                }
                used |= slot_bit;
            }
            if (!collided)
            {
                found_magic = magic;
                found_shift = shift;
                break :search;
            }
        }
    }

    if (found_magic) |magic|
    {
        const table_header = "static const uint64_t TABLE_FIB[] = {\n";
        const table_closer = "};\n";

        try interface.writeAll(table_header);
        for (nums.items, strings.items) |n, s| try interface.print("\t[{d:<3}] = 0x{X:0>16}, // {s}\n", .{ (n *% magic) >> found_shift, n, s });
        try interface.writeAll(table_closer);

        const fmt =
            \\#ifdef __GNUC__
            \\__attribute__((__always_inline__, const, __flatten__, __unused__))
            \\#endif
            \\#ifdef __cplusplus
            \\constexpr
            \\#endif
            \\static inline uint64_t
            \\fib_hash(uint64_t input)
            \\#ifdef __cplusplus
            \\noexcept
            \\#endif
            \\{{
            \\  return ((input * 0x{x}) >> {d});
            \\}}
            ;
        try interface.print(fmt ++ "\n", .{magic, found_shift});
    }
    try interface.writeAll("#undef FBHC_CONSTEXPR\n");
}
