const std = @import("std");
const builtin = @import("builtin");
const Lexer = @import("root.zig").Lexer;
const Runner = @import("root.zig").Runner;

pub fn main() !void {
    var ally = if (builtin.mode == .Debug) std.heap.GeneralPurposeAllocator(.{}){} else std.heap.page_allocator;
    defer if (builtin.mode == .Debug) {
        _ = ally.deinit();
    };

    const alloc = if (builtin.mode == .Debug)
        ally.allocator()
    else
        ally;
    var args = try std.process.ArgIterator.initWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();
    const arg1 = args.next();
    var file = if (arg1) |file_name| blk: {
        break :blk std.fs.cwd().openFile(file_name, .{}) catch @panic("Error opening file");
    } else @panic("No input filename declared");
    const content = try file.readToEndAlloc(alloc, std.fs.MAX_PATH_BYTES);
    defer alloc.free(content);
    var lexer = Lexer.init(alloc, @constCast(content));
    defer lexer.deinit();
    const tokens = try lexer.parse();
    defer alloc.free(tokens);
    var runner = Runner.new(tokens);
    try runner.run();
}
