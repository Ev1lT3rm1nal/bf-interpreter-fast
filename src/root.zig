const std = @import("std");

pub const Token = union(enum) {
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
    seek_zero_left,
    seek_zero_right,
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    pointer: usize = 0,
    program: []u8,

    pub fn nextToken(self: *Lexer) ?u8 {
        if (self.pointer >= self.program.len) {
            return null;
        }
        const current = self.program[self.pointer];

        self.pointer += 1;
        return current;
    }

    pub fn new(allocator: std.mem.Allocator, program: []u8) Lexer {
        return Lexer{
            .allocator = allocator,
            .program = program,
        };
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

    fn optimizeCode(self: *Lexer) void {
        const previous_size = self.program.len;
        var new_size = previous_size;
        new_size -= std.mem.replace(u8, self.program, "[-]", "z", self.program) * 2;
        new_size -= std.mem.replace(u8, self.program, "[+]", "z", self.program) * 2;
        new_size -= std.mem.replace(u8, self.program, "[<]", "l", self.program) * 2;
        new_size -= std.mem.replace(u8, self.program, "[r]", "r", self.program) * 2;
        new_size -= std.mem.replace(u8, self.program, "[]", "", self.program) * 2;
        self.program = self.program[0..new_size];
        if (new_size < previous_size) {
            self.optimizeCode();
        }
    }

    pub fn optimizeTokens(self: *Lexer, tokens: []Token) ![]Token {
        var optimized_tokens = try std.ArrayList(Token).initCapacity(self.allocator, tokens.len);
        defer optimized_tokens.deinit();

        var index: usize = 0;
        while (index < tokens.len) : (index += 1) {
            if (index + 5 < tokens.len and match_pattern(&[_]@typeInfo(Token).Union.tag_type.?{
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

            try optimized_tokens.append(tokens[index]);
        }

        return optimized_tokens.toOwnedSlice();
    }

    pub fn matchBrackets(self: *Lexer, tokens: *[]Token) !void {
        var bracketStack = std.ArrayList(usize).init(self.allocator);
        defer bracketStack.deinit();

        for (tokens.*, 0..) |*token, index| {
            switch (token.*) {
                .l_array => {
                    try bracketStack.append(index);
                    token.l_array = 0; // Se actualizará después de encontrar el corchete de cierre correspondiente
                },
                .r_array => {
                    // Verifica si hay un corchete de apertura correspondiente

                    // Obtiene la posición del corchete de apertura y hace que coincida con el corchete de cierre
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
        self.optimizeCode();
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
                'z' => {
                    try tokens.append(Token.zero);
                    next_token = self.nextToken();
                },
                'l' => {
                    try tokens.append(Token.seek_zero_left);
                    next_token = self.nextToken();
                },
                'r' => {
                    try tokens.append(Token.seek_zero_right);
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
                    @setRuntimeSafety(false);
                    self.memory[self.memory_pointer] = @intCast(addition +% @as(isize, self.memory[self.memory_pointer]));
                },
                Token.shifting => |shift| {
                    @setRuntimeSafety(false);
                    const pointer: usize = @intCast(shift +% @as(isize, @intCast(self.memory_pointer)));
                    self.memory_pointer = pointer;
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
                Token.seek_zero_left => {
                    while (self.memory[self.memory_pointer] != 0) {
                        self.memory_pointer -= 1;
                    }
                },
                Token.seek_zero_right => {
                    while (self.memory[self.memory_pointer] != 0) {
                        self.memory_pointer += 1;
                    }
                },
            }
        }

        try buf.flush();
    }
};

pub fn match_pattern(pattern: []const @typeInfo(Token).Union.tag_type.?, values: []const Token) bool {
    if (pattern.len != values.len) {
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
    try std.testing.expect(match_pattern(&[_]@typeInfo(Token).Union.tag_type.?{
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
    var lexer = Lexer.new(std.testing.allocator, @constCast("+++++[->>>>+<<<<]"));
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    const com_tokens = [_]@typeInfo(Token).Union.tag_type.?{
        Token.addition,
        Token.multiply,
    };
    try std.testing.expect(match_pattern(&com_tokens, tokens));
}

test "memory" {
    var lexer = Lexer.new(std.testing.allocator, @constCast("+++++[->>>>+<<<<]"));
    const tokens = try lexer.parse();
    defer std.testing.allocator.free(tokens);
    var runner = Runner.new(tokens);
    try runner.run();
    try std.testing.expect(runner.memory[4] == 5);
}

// test "brackets" {
//     const Token = Token;
//     _ = Token; // autofix
//     var lexer = Lexer.init(std.testing.allocator, @constCast("+++++[->>>>+++<<<<]"));
//     const tokens = try lexer.parse();
//     defer std.testing.allocator.free(tokens);
// }
