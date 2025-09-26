const std = @import("std");

const behaviour = @import("options").arraybounds;

const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;
const Lexer = @import("lexer.zig").Lexer;

const matchPattern = @import("lexer.zig").matchPattern;

const TokenList = std.MultiArrayList(Token);

const HeapSize = 1 << 15;

const is_debug = @import("builtin").mode == .Debug;

pub const Runner = struct {
    program: []Token,

    pub fn new(tokens: []Token) Runner {
        return .{ .program = tokens };
    }

    pub fn run(self: *Runner, allocator: std.mem.Allocator) !void {
        const stdOut = std.io.getStdOut().writer();
        const stdIn = std.io.getStdIn().reader();
        var buf = std.io.BufferedWriter(1024, @TypeOf(stdOut)){ .unbuffered_writer = stdOut };

        var program_fast = TokenList{};
        defer program_fast.deinit(allocator);

        for (self.program) |token| {
            try program_fast.append(allocator, token);
        }

        const sliced = program_fast.slice();

        const token_types = sliced.items(.tags);
        const data = sliced.items(.data);

        var memory: [HeapSize]u8 = @splat(0);
        var memory_pointer: usize = 0;
        var program_pointer: usize = 0;

        // Get the Writer interface from BufferedWriter
        var writer = buf.writer();

        computed: switch (token_types[program_pointer]) {
            Token.addition => {
                const addition = data[program_pointer].addition;
                const sum: usize = @abs(addition);
                if (addition > 0) {
                    memory[memory_pointer] +%= @intCast(sum);
                } else {
                    memory[memory_pointer] -%= @intCast(sum);
                }
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.shifting => {
                @setRuntimeSafety(behaviour == .Abort or is_debug);

                const shift = data[program_pointer].shifting;
                var pointer = @as(isize, @intCast(memory_pointer)) + shift;

                if (behaviour == .Wrap) {
                    if (pointer >= HeapSize) {
                        pointer -= HeapSize;
                    } else if (pointer < 0) {
                        pointer += HeapSize;
                    }
                } else if (behaviour == .Block) {
                    if (pointer >= HeapSize) {
                        pointer = HeapSize - 1;
                    } else if (pointer < 0) {
                        pointer = 0;
                    }
                }

                memory_pointer = @intCast(pointer);
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.output => {
                try writer.writeByte(memory[memory_pointer]);
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.input => {
                try buf.flush();
                const out = stdIn.readByte() catch null;
                if (out) |char| {
                    memory[memory_pointer] = char;
                }
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.l_array => {
                const matching_r_array_pos = data[program_pointer].l_array;
                if (memory[memory_pointer] == 0) {
                    program_pointer = matching_r_array_pos;
                }
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.r_array => {
                const matching_l_array_pos = data[program_pointer].r_array;
                if (memory[memory_pointer] != 0) {
                    program_pointer = matching_l_array_pos;
                }
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.multiply => {
                @setRuntimeSafety(is_debug);
                const value = data[program_pointer].multiply;
                const index: usize = @intCast(@as(isize, @intCast(memory_pointer)) + value.where);
                const memory_value: u8 = @intCast(@as(isize, @intCast(memory[memory_pointer])) * value.value);
                memory[index] += memory_value;
                memory[memory_pointer] = 0;
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.zero => {
                memory[memory_pointer] = 0;
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.seek_zero => {
                const step = data[program_pointer].seek_zero;
                while (memory[memory_pointer] != 0) {
                    memory_pointer = @intCast(@as(isize, @intCast(memory_pointer)) + step);
                }
                program_pointer += 1;
                continue :computed token_types[program_pointer];
            },
            Token.end => break :computed,
        }

        try buf.flush();

        // @memcpy(&self.memory, memory[0..]);
        // self.memory_pointer = memory_pointer;
        // self.program_pointer = program_pointer;
    }
};

// test "memory" {
//     var testing = "+++++[->>>>+<<<<]".*;
//     var lexer = Lexer.new(std.testing.allocator, &testing);
//     const tokens = try lexer.parse();
//     defer std.testing.allocator.free(tokens);
//     var runner = Runner.new(tokens);
//     try runner.run(std.testing.allocator);
//     try std.testing.expect(runner.memory[4] == 5);
// }

// test "seek zero" {
//     var testing = "+++++[->+>+>+>+>+>+<<<<<<]>[>>]".*;
//     var lexer = Lexer.new(std.testing.allocator, &testing);
//     const tokens = try lexer.parse();
//     defer std.testing.allocator.free(tokens);
//     var runner = Runner.new(tokens);
//     try runner.run(std.testing.allocator);
//     try std.testing.expect(runner.memory_pointer == 7);
// }

// test "infinity loop" {
//     var testing = "+[[]]".*;
//     var lexer = Lexer.new(std.testing.allocator, &testing);
//     const tokens = try lexer.parse();
//     defer std.testing.allocator.free(tokens);
//     var runner = Runner.new(tokens);
//     try runner.run(std.testing.allocator);
//     try std.testing.expect(runner.memory[0] == 1);
// }

// test "wrapping memory" {
//     if (behaviour != .Wrap) {
//         return;
//     }
//     var testing = "<".*;
//     var lexer = Lexer.new(std.testing.allocator, &testing);
//     const tokens = try lexer.parse();
//     defer std.testing.allocator.free(tokens);
//     var runner = Runner.new(tokens);
//     try runner.run(std.testing.allocator);
//     try std.testing.expect(runner.memory_pointer == 29999);
// }

// test "wrapping byte" {
//     if (behaviour != .Wrap) {
//         return;
//     }
//     var testing = "-".*;
//     var lexer = Lexer.new(std.testing.allocator, &testing);
//     const tokens = try lexer.parse();
//     defer std.testing.allocator.free(tokens);
//     var runner = Runner.new(tokens);
//     try runner.run(std.testing.allocator);
//     try std.testing.expect(runner.memory[runner.memory_pointer] == 255);
// }
