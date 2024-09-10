const std = @import("std");

const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;
const Lexer = @import("lexer.zig").Lexer;

const matchPattern = @import("lexer.zig").matchPattern;

const TokenList = std.MultiArrayList(Token);

const HeapSize = 30000;

pub const Runner = struct {
    memory: [HeapSize]u8 = [_]u8{0} ** HeapSize,
    program: []Token,
    program_pointer: usize = 0,
    memory_pointer: usize = 0,

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

        // Get the Writer interface from BufferedWriter
        var writer = buf.writer();

        computed: switch (token_types[self.program_pointer]) {
            Token.addition => {
                const addition = data[self.program_pointer].addition;
                const sum: usize = @abs(addition);
                if (addition > 0) {
                    self.memory[self.memory_pointer] +%= @intCast(sum);
                } else {
                    self.memory[self.memory_pointer] -%= @intCast(sum);
                }
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.shifting => {
                const shift = data[self.program_pointer].shifting;
                var pointer = @as(isize, @intCast(self.memory_pointer)) + shift;

                if (pointer >= HeapSize) {
                    pointer -= HeapSize;
                } else if (pointer < 0) {
                    pointer += HeapSize;
                }

                self.memory_pointer = @intCast(pointer);
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.output => {
                try writer.print("{c}", .{self.memory[self.memory_pointer]});
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.input => {
                try buf.flush();
                self.memory[self.memory_pointer] = try stdIn.readByte();
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.l_array => {
                const matching_r_array_pos = data[self.program_pointer].l_array;
                if (self.memory[self.memory_pointer] == 0) {
                    self.program_pointer = matching_r_array_pos;
                }
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.r_array => {
                const matching_l_array_pos = data[self.program_pointer].r_array;
                if (self.memory[self.memory_pointer] != 0) {
                    self.program_pointer = matching_l_array_pos;
                }
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.multiply => {
                const value = data[self.program_pointer].multiply;
                @setRuntimeSafety(false);
                self.memory[
                    @intCast(@as(isize, @intCast(self.memory_pointer)) + value.where)
                ] += @intCast(@as(isize, @intCast(self.memory[self.memory_pointer])) * value.value);
                self.memory[self.memory_pointer] = 0;
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.zero => {
                self.memory[self.memory_pointer] = 0;
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.seek_zero => {
                const step = data[self.program_pointer].seek_zero;
                while (self.memory[self.memory_pointer] != 0) {
                    self.memory_pointer = @intCast(@as(isize, @intCast(self.memory_pointer)) + step);
                }
                self.program_pointer += 1;
                continue :computed token_types[self.program_pointer];
            },
            Token.end => break :computed,
        }

        try buf.flush();
    }
};

test "parsing" {
    var testing = "+++++[->>>>+<<<<]".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    const com_tokens = [_]TokenType{
        Token.addition,
        Token.multiply,
    };
    try std.testing.expect(matchPattern(&com_tokens, tokens));
}

test "memory" {
    var testing = "+++++[->>>>+<<<<]".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    var runner = Runner.new(tokens);
    try runner.run();
    try std.testing.expect(runner.memory[4] == 5);
}

test "seek zero" {
    var testing = "+++++[->+>+>+>+>+>+<<<<<<]>[>>]".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    var runner = Runner.new(tokens);
    try runner.run();
    try std.testing.expect(runner.memory_pointer == 7);
}

test "set zero" {
    var testing = "+++[++++++[-]]".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    const com_tokens = [_]TokenType{
        Token.zero,
    };
    try std.testing.expect(matchPattern(&com_tokens, tokens));
}

test "zero repeating" {
    var testing = "[[[[-]]]]".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    const com_tokens = [_]TokenType{
        Token.zero,
    };
    try std.testing.expect(matchPattern(&com_tokens, tokens));
}

test "infinity loop" {
    var testing = "+[[]]".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    var runner = Runner.new(tokens);
    try runner.run();
    try std.testing.expect(runner.memory[0] == 1);
}

test "optimized away" {
    var testing = ">>>>+++++[[]]-----<<<<".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens.len == 0);
}

test "wrapping memory" {
    var testing = "<".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    var runner = Runner.new(tokens);
    try runner.run();
    try std.testing.expect(runner.memory_pointer == 29999);
}

test "wrapping byte" {
    var testing = "-".*;
    var lexer = Lexer.new(std.testing.allocator, &testing);
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    var runner = Runner.new(tokens);
    try runner.run();
    try std.testing.expect(runner.memory[runner.memory_pointer] == 255);
}
