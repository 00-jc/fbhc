//! SIMD whitespace tokenizer that packs each keyword into a little-endian `K`.

const std = @import("std");

const Vec = @Vector(std.simd.suggestVectorLength(u8).?, u8);
const UnalignedVecPtr = [*]align(1) const Vec;

pub fn Tokens(comptime K: type) type
{
    return struct {
        nums: std.ArrayList(K),
        strings: std.ArrayList([]const u8),

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void
        {
            self.nums.deinit(allocator);
            self.strings.deinit(allocator);
        }
    };
}

inline fn pack(comptime K: type, tok: []const u8) K
{
    var buf: [@sizeOf(K)]u8 = @splat(0);
    @memcpy(buf[0..tok.len], tok);
    return std.mem.readInt(K, &buf, .little);
}

pub fn tokenize(comptime K: type, allocator: std.mem.Allocator, src: []const u8) !Tokens(K)
{
    const max_len = @sizeOf(K);
    const tail_start = src.len - (src.len & (@sizeOf(Vec) - 1));
    var it: usize = 0;
    var safe_buf: [@sizeOf(Vec)]u8 = @splat(' ');
    @memcpy(safe_buf[0 .. src.len - tail_start], src[tail_start..]);

    var out: Tokens(K) = .{
        .nums = try .initCapacity(allocator, 32),
        .strings = try .initCapacity(allocator, 32),
    };
    errdefer out.deinit(allocator);

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
            if ((it + e) - s > max_len) return error.KeyTooLong;
            try out.strings.append(allocator, src[s .. it + e]);
            try out.nums.append(allocator, pack(K, src[s .. it + e]));
        }
        carry = @truncate(mask >> (bits - 1));
        const has = 0 -% @as(usize, @intFromBool(starts != 0));
        const top = (bits - 1) -% @as(usize, @clz(starts));
        tok_start = ((it +% top) & has) | (tok_start & ~has);
    }
    if (carry == 1)
    {
        if (src.len - tok_start > max_len) return error.KeyTooLong;
        try out.strings.append(allocator, src[tok_start..]);
        try out.nums.append(allocator, pack(K, src[tok_start..]));
    }
    return out;
}
