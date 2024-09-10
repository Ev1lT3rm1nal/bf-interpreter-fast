pub usingnamespace @import("lexer.zig");
pub usingnamespace @import("runner.zig");

// test "block zero memory" {
//     var lexer = Lexer.new(std.testing.allocator, @constCast("+++++++++++[->+>+>+>+>+>+<<<<<<]>[-]>[-]>[-]>[-]>[-]>[-]"));
//     const tokens = try lexer.parse();
//     defer std.testing.allocator.free(tokens);
//     var runner = Runner.new(tokens);
//     try runner.run();
//     try std.testing.expect(runner.memory_pointer == 6);
//     try std.testing.expect(std.mem.allEqual(u8, runner.memory[0..10], 0));
// }
