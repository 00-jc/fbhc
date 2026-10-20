//! Command line parsing.

const std = @import("std");

pub const Options = struct {
    path: []const u8,
    use128: bool = false,
};

pub fn parse(arg_it: anytype) !Options
{
    var path: ?[]const u8 = null;
    var use128 = false;
    _ = arg_it.skip();
    while (arg_it.next()) |arg|
    {
        if (std.mem.eql(u8, arg, "--use128")) use128 = true
        else if (std.mem.startsWith(u8, arg, "--")) return error.UnknownFlag
        else if (path == null) path = arg
        else return error.TooManyFiles;
    }
    return .{ .path = path orelse return error.NoFileInArgs, .use128 = use128 };
}
