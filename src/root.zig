const std = @import("std");

pub const Token = union(enum) {
    addition: isize,
    shifting: isize,
    l_array: usize,
    r_array: usize,
    input,
    output,
    zero,
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(Token),
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

    pub fn init(allocator: std.mem.Allocator, program: []u8) Lexer {
        return Lexer{
            .allocator = allocator,
            .tokens = std.ArrayList(Token).init(allocator),
            .program = program,
        };
    }

    pub fn stripComments(self: *Lexer) void {
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

    pub fn optimize(self: *Lexer) !void {
        self.program = try std.mem.replaceOwned(u8, self.allocator, self.program, "[-]", "z");
    }

    pub fn parse(self: *Lexer) ![]Token {
        self.stripComments();
        try self.optimize();
        defer self.allocator.free(self.program);
        var next_token: ?u8 = self.nextToken();
        var stack_count: usize = 0;

        var bracketStack = std.ArrayList(usize).init(self.allocator);
        defer bracketStack.deinit();

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
                        try self.tokens.append(Token{ .addition = counter });
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
                        try self.tokens.append(Token{ .shifting = counter });
                    }
                },
                '[' => {
                    try bracketStack.append(self.tokens.items.len);
                    try self.tokens.append(Token{ .l_array = 0 });
                    next_token = self.nextToken();
                    stack_count += 1;
                },
                ']' => {
                    if (stack_count == 0) {
                        return error.UnbalancedLoop;
                    }
                    const openingBracketPos = bracketStack.pop();
                    self.tokens.items[openingBracketPos] = Token{ .l_array = self.tokens.items.len };
                    try self.tokens.append(Token{ .r_array = openingBracketPos });
                    next_token = self.nextToken();
                    stack_count -= 1;
                },
                '.' => {
                    try self.tokens.append(Token.output);
                    next_token = self.nextToken();
                },
                ',' => {
                    try self.tokens.append(Token.input);
                    next_token = self.nextToken();
                },
                'z' => {
                    try self.tokens.append(Token.zero);
                    next_token = self.nextToken();
                },
                else => unreachable,
            }
        }

        if (stack_count > 0) {
            return error.UnbalancedLoop;
        }
        return try self.tokens.toOwnedSlice();
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
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
                    self.memory[self.memory_pointer] = @intCast(addition + @as(isize, self.memory[self.memory_pointer]));
                },
                Token.shifting => |shift| {
                    @setRuntimeSafety(false);
                    const pointer: usize = @intCast(shift + @as(isize, @intCast(self.memory_pointer)));
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
                Token.zero => {
                    self.memory[self.memory_pointer] = 0;
                },
            }
        }

        try buf.flush();
    }
};
