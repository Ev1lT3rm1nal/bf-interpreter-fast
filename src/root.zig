const std = @import("std");

pub const TokenType = enum(u8) {
    addition,
    shifting,
    l_array,
    r_array,
    multiply,
    input,
    output,
    zero,
    seek_zero,
};

pub const Token = union(TokenType) {
    addition: isize,
    shifting: isize,
    l_array: usize,
    r_array: usize,
    multiply: struct {
        where: isize,
        value: isize,
    },
    input,
    output,
    zero,
    seek_zero: isize,
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    pointer: usize = 0,
    program: []u8,

    pub fn new(allocator: std.mem.Allocator, program: []u8) Lexer {
        return Lexer{
            .allocator = allocator,
            .program = program,
        };
    }

    pub fn nextToken(self: *Lexer) ?u8 {
        if (self.pointer >= self.program.len) {
            return null;
        }
        const current = self.program[self.pointer];

        self.pointer += 1;
        return current;
    }

    fn stripComments(self: *Lexer) void {
        var readIndex: usize = 0;
        var writeIndex: usize = 0;
        while (readIndex < self.program.len) {
            switch (self.program[readIndex]) {
                '+', '-', '<', '>', '[', ']', ',', '.' => {
                    self.program[writeIndex] = self.program[readIndex];
                    writeIndex += 1;
                },
                else => {},
            }
            readIndex += 1;
        }
        self.program = self.program[0..writeIndex];
    }

    pub fn optimizeTokens(self: *Lexer, tokens: []Token) ![]Token {
        var optimized_tokens = try std.ArrayList(Token).initCapacity(self.allocator, tokens.len);
        defer optimized_tokens.deinit();

        var new_size = tokens.len;

        var index: usize = 0;
        while (index < tokens.len) : (index += 1) {
            // Check if is the a loop for copying values
            // Example [->>>>+<<<<]
            if (index + 5 < tokens.len and matchPattern(&[_]TokenType{
                Token.l_array,
                Token.addition,
                Token.shifting,
                Token.addition,
                Token.shifting,
                Token.r_array,
            }, tokens[index .. index + 6]) and tokens[index + 1].addition == -1 and tokens[index + 3].addition > 0 and
                tokens[index + 2].shifting == -tokens[index + 4].shifting)
            {
                try optimized_tokens.append(Token{ .multiply = .{
                    .where = tokens[index + 2].shifting,
                    .value = tokens[index + 3].addition,
                } });
                index += 5;
                continue;
            }

            // Seek zero finder
            // Example [>>>]
            if (index + 2 < tokens.len and matchPattern(&[_]TokenType{
                Token.l_array,
                Token.shifting,
                Token.r_array,
            }, tokens[index .. index + 3])) {
                try optimized_tokens.append(Token{ .seek_zero = tokens[index + 1].shifting });
                index += 2;
                continue;
            }

            // Set cell to zero
            // Example [-] or [+] or even [++++]
            if (index + 2 < tokens.len and matchPattern(&[_]TokenType{
                Token.l_array,
                Token.addition,
                Token.r_array,
            }, tokens[index .. index + 3])) {
                try optimized_tokens.append(Token.zero);
                index += 2;
                continue;
            }

            // Find looping zero value
            if (index + 2 < tokens.len and matchPattern(&[_]TokenType{
                Token.l_array,
                Token.zero,
                Token.r_array,
            }, tokens[index .. index + 3])) {
                try optimized_tokens.append(Token.zero);
                index += 2;
                continue;
            }

            // Delete extra additions that are useless
            if (index + 1 < tokens.len and matchPattern(&[_]TokenType{
                Token.addition,
                Token.zero,
            }, tokens[index .. index + 2])) {
                try optimized_tokens.append(Token.zero);
                index += 1;
                continue;
            }

            // Detects empty brackets, this disables infinity loops
            if (index + 1 < tokens.len and matchPattern(&[_]TokenType{
                Token.l_array,
                Token.r_array,
            }, tokens[index .. index + 2])) {
                index += 1;
                continue;
            }

            // Detects repeating additions
            if (index + 1 < tokens.len and matchPattern(&[_]TokenType{
                Token.addition,
                Token.addition,
            }, tokens[index .. index + 2])) {
                const value = tokens[index].addition + tokens[index + 1].addition;
                if (value != 0) {
                    try optimized_tokens.append(Token{ .addition = value });
                }
                index += 1;
                continue;
            }

            // Detects repeating shiftings
            if (index + 1 < tokens.len and matchPattern(&[_]TokenType{
                Token.shifting,
                Token.shifting,
            }, tokens[index .. index + 2])) {
                const value = tokens[index].shifting + tokens[index + 1].shifting;
                if (value != 0) {
                    try optimized_tokens.append(Token{ .addition = value });
                }
                index += 1;
                continue;
            }

            try optimized_tokens.append(tokens[index]);
        }

        new_size -= optimized_tokens.items.len;

        if (new_size == 0) {
            return optimized_tokens.toOwnedSlice();
        } else {
            return self.optimizeTokens(optimized_tokens.items);
        }
    }

    pub fn matchBrackets(self: *Lexer, tokens: *[]Token) !void {
        var bracketStack = std.ArrayList(usize).init(self.allocator);
        defer bracketStack.deinit();

        for (tokens.*, 0..) |*token, index| {
            switch (token.*) {
                .l_array => {
                    try bracketStack.append(index);
                },
                .r_array => {
                    const openingBracketPos = bracketStack.pop();
                    tokens.*[openingBracketPos].l_array = index;
                    token.r_array = openingBracketPos;
                },
                else => {},
            }
        }
    }

    pub fn parse(self: *Lexer) ![]Token {
        self.stripComments();
        var next_token: ?u8 = self.nextToken();
        var stack_count: usize = 0;

        var tokens = std.ArrayList(Token).init(self.allocator);
        defer tokens.deinit();

        while (next_token) |token| {
            switch (token) {
                '+', '-' => {
                    var counter: isize = if (token == '+') 1 else -1;
                    var next = self.nextToken();
                    while (next == '+' or next == '-') {
                        counter += if (next == '+') 1 else -1;
                        next = self.nextToken();
                    }
                    next_token = next;
                    if (counter != 0) {
                        try tokens.append(Token{ .addition = counter });
                    }
                },
                '>', '<' => {
                    var counter: isize = if (token == '>') 1 else -1;
                    var next = self.nextToken();
                    while (next == '>' or next == '<') {
                        counter += if (next == '>') 1 else -1;
                        next = self.nextToken();
                    }
                    next_token = next;
                    if (counter != 0) {
                        try tokens.append(Token{ .shifting = counter });
                    }
                },
                '[' => {
                    try tokens.append(Token{ .l_array = 0 });
                    next_token = self.nextToken();
                    stack_count += 1;
                },
                ']' => {
                    if (stack_count == 0) {
                        return error.UnbalancedLoop;
                    }
                    try tokens.append(Token{ .r_array = 0 });
                    next_token = self.nextToken();
                    stack_count -= 1;
                },
                '.' => {
                    try tokens.append(Token.output);
                    next_token = self.nextToken();
                },
                ',' => {
                    try tokens.append(Token.input);
                    next_token = self.nextToken();
                },
                else => unreachable,
            }
        }

        if (stack_count > 0) {
            return error.UnbalancedLoop;
        }
        var optimized = try self.optimizeTokens(tokens.items);

        try self.matchBrackets(&optimized);

        return optimized;
    }
};

const HeapSize = 30000;

pub const Runner = struct {
    memory: [HeapSize]u8 = [_]u8{0} ** HeapSize,
    program: []Token,
    program_pointer: usize = 0,
    memory_pointer: usize = 0,

    pub fn new(tokens: []Token) Runner {
        return .{ .program = tokens };
    }

    pub fn run(self: *Runner) !void {
        const stdOut = std.io.getStdOut().writer();
        const stdIn = std.io.getStdIn().reader();
        var buf = std.io.BufferedWriter(1024, @TypeOf(stdOut)){ .unbuffered_writer = stdOut };

        // Get the Writer interface from BufferedWriter
        var writer = buf.writer();
        while (self.program_pointer < self.program.len) : (self.program_pointer += 1) {
            const token = self.program[self.program_pointer];
            switch (token) {
                Token.addition => |addition| {
                    const sum: usize = @abs(addition);
                    if (addition > 0) {
                        self.memory[self.memory_pointer] +%= @intCast(sum);
                    } else {
                        self.memory[self.memory_pointer] -%= @intCast(sum);
                    }
                },
                Token.shifting => |shift| {
                    var pointer = @as(isize, @intCast(self.memory_pointer)) + shift;

                    if (pointer >= HeapSize) {
                        pointer -= HeapSize;
                    } else if (pointer < 0) {
                        pointer += HeapSize;
                    }

                    self.memory_pointer = @intCast(pointer);
                },
                Token.output => {
                    try writer.print("{c}", .{self.memory[self.memory_pointer]});
                },
                Token.input => {
                    try buf.flush();
                    self.memory[self.memory_pointer] = try stdIn.readByte();
                },
                Token.l_array => |matching_r_array_pos| {
                    if (self.memory[self.memory_pointer] == 0) {
                        self.program_pointer = matching_r_array_pos;
                    }
                },
                Token.r_array => |matching_l_array_pos| {
                    if (self.memory[self.memory_pointer] != 0) {
                        self.program_pointer = matching_l_array_pos;
                    }
                },
                Token.multiply => |value| {
                    @setRuntimeSafety(false);
                    self.memory[
                        @intCast(@as(isize, @intCast(self.memory_pointer)) + value.where)
                    ] += @intCast(@as(isize, @intCast(self.memory[self.memory_pointer])) * value.value);
                    self.memory[self.memory_pointer] = 0;
                },
                Token.zero => {
                    self.memory[self.memory_pointer] = 0;
                },
                Token.seek_zero => |step| {
                    while (self.memory[self.memory_pointer] != 0) {
                        self.memory_pointer = @intCast(@as(isize, @intCast(self.memory_pointer)) + step);
                    }
                },
            }
        }

        try buf.flush();
    }
};

pub fn matchPattern(pattern: []const TokenType, values: []const Token) bool {
    if (pattern.len != values.len) {
        @branchHint(.cold);
        @panic("lenght must be equal");
    }
    for (values, 0..) |value, index| {
        if (value != pattern[index]) {
            return false;
        }
    }
    return true;
}

test "match pattern" {
    try std.testing.expect(matchPattern(&[_]TokenType{
        Token.l_array,
        Token.addition,
        Token.shifting,
        Token.addition,
        Token.shifting,
        Token.r_array,
    }, &[_]Token{
        Token{ .l_array = 6 },
        Token{ .addition = -1 },
        Token{ .shifting = 4 },
        Token{ .addition = 1 },
        Token{ .shifting = -4 },
        Token{ .r_array = 1 },
    }));
}

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

// test "block zero memory" {
//     var lexer = Lexer.new(std.testing.allocator, @constCast("+++++++++++[->+>+>+>+>+>+<<<<<<]>[-]>[-]>[-]>[-]>[-]>[-]"));
//     const tokens = try lexer.parse();
//     defer std.testing.allocator.free(tokens);
//     var runner = Runner.new(tokens);
//     try runner.run();
//     try std.testing.expect(runner.memory_pointer == 6);
//     try std.testing.expect(std.mem.allEqual(u8, runner.memory[0..10], 0));
// }
