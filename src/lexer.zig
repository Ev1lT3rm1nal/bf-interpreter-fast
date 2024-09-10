const std = @import("std");

pub const TokenType = enum(u8) {
    end,
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
    end,
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

    fn optimizeTokens(self: *Lexer, tokens: []Token) ![]Token {
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

    // pub fn optimizeTokens(self: *Lexer, tokens: []Token) ![]Token {}

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
