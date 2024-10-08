const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Each subsequent command builds off the representation
// of the culmination of everything prior. In a way this
// is more like append-only Event Sourcing where the result
// is the sum of all prior commands.
//
// Piece { .op, .string, .start }
//
// Op.origin + Op.add (=new origin) + Op.delete (=new origin):
//
// Piece(Op.origin, "Hello World", 0)
// H e l l o   W o r l d  \n
// 0 1 2 3 4 5 6 7 8 9 10 11
//
// Piece(Op.add, "There ", 6)
// H e l l o   T h e r e     W  o  r  l  d  \n
// 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17
//
// Piece(Op.delete, "llo The", 2)
// H e r e   W o r l d \n
// 0 1 2 3 4 5 6 7 8 9 10
//
// Op.delete + Op.add ("replace") (=new origin):
//
// Piece(Op.delete, "Here", 0)
// Piece(Op.add, "Sup", 0)
// S u p   W o r l d \n
// 0 1 2 3 4 5 6 7 8 9

const Op = enum {
    origin,
    add,
    delete,
};

pub fn PieceTable() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        root: ArrayList(Piece),

        const Piece = struct {
            op: Op,
            string: []const u8,
            start: usize,
            active: bool,

            fn init(op: Op, string: []const u8, start: usize) Piece {
                return Piece{
                    .op = op,
                    .string = string,
                    .start = start,
                    .active = true,
                };
            }
        };

        pub fn init(allocator: Allocator) Self {
            const root = ArrayList(Piece).init(allocator);
            return .{
                .allocator = allocator,
                .root = root,
            };
        }

        pub fn len(self: *Self) usize {
            return self.root.items.len;
        }

        pub fn append(self: *Self, op: Op, string: []const u8, start: usize) !void {
            for (0..self.root.items.len) |i| {
                self.root.items[i].active = false;
            }
            const piece = Piece.init(op, string, start);
            try self.root.append(piece);
        }

        pub fn replace(self: *Self, old: []const u8, new: []const u8, start: usize) !void {
            try self.append(Op.delete, old, start);
            try self.append(Op.add, new, start);
        }

        // Caller owns and must free the returned slice with the same allocator
        pub fn replay(self: *Self) ![]const u8 {
            var origin = std.ArrayList(u8).init(self.allocator);
            defer origin.deinit();

            if (self.root.items.len > 0) {
                var i: usize = 0;
                while (i <= self.compute_idx()) : (i += 1) {
                    const piece = self.root.items[i];
                    switch (piece.op) {
                        Op.origin => try origin.appendSlice(piece.string),
                        Op.add => try origin.insertSlice(piece.start, piece.string),
                        Op.delete => {
                            for (0..piece.string.len) |_| {
                                _ = origin.orderedRemove(piece.start);
                            }
                        },
                    }
                }
            }

            return origin.toOwnedSlice();
        }

        fn compute_idx(self: *Self) usize {
            var i: usize = 0;
            for (0..self.root.items.len) |idx| {
                if (self.root.items[idx].active == false) i += 1 else break;
            }
            return i;
        }

        pub fn undo(self: *Self) void {
            const idx = self.compute_idx();
            if (idx == 0) return;
            if (self.root.items.len > 0) {
                self.root.items[idx].active = false;
                self.root.items[idx - 1].active = true;
            }
        }

        pub fn redo(self: *Self) void {
            const idx = self.compute_idx();
            if (idx < self.root.items.len - 1) {
                self.root.items[idx + 1].active = true;
                self.root.items[idx].active = false;
            }
        }

        pub fn deinit(self: *Self) void {
            self.root.deinit();
        }
    };
}

test "Piece: init" {
    const piece = PieceTable().Piece.init(Op.origin, "Hello World\n", 0);
    try testing.expect(piece.op == Op.origin);
    try testing.expect(std.mem.eql(u8, "Hello World\n", piece.string));
    try testing.expect(piece.start == 0);
}

test "PieceTable: init, append, len, replay" {
    const allocator = testing.allocator;

    var pt = PieceTable().init(allocator);
    defer pt.deinit();

    try testing.expect(pt.len() == 0);
    try pt.append(Op.origin, "Hello World\n", 0);
    try testing.expect(pt.len() == 1);
    try testing.expectEqual(pt.root.items[0].string, "Hello World\n");
    var result = try pt.replay();
    try testing.expect(std.mem.eql(u8, "Hello World\n", result));
    allocator.free(result);

    try pt.append(Op.add, "There ", 6);
    try testing.expect(pt.len() == 2);
    result = try pt.replay();
    try testing.expect(std.mem.eql(u8, "Hello There World\n", result));
    allocator.free(result);

    try pt.append(Op.delete, "llo The", 2);
    try testing.expect(pt.len() == 3);
    result = try pt.replay();
    try testing.expect(std.mem.eql(u8, "Here World\n", result));
    allocator.free(result);

    try pt.replace("Here", "Sup", 0);
    try testing.expect(pt.len() == 5); // delete + add
    result = try pt.replay();
    try testing.expect(std.mem.eql(u8, "Sup World\n", result));
    allocator.free(result);

    pt.undo();
    result = try pt.replay();
    try testing.expect(std.mem.eql(u8, " World\n", result));
    allocator.free(result);

    pt.redo();
    result = try pt.replay();
    try testing.expect(std.mem.eql(u8, "Sup World\n", result));
    allocator.free(result);

    pt.undo();
    pt.undo();
    result = try pt.replay();
    try testing.expect(std.mem.eql(u8, "Here World\n", result));
    allocator.free(result);
}

test "PieceTable: undo, redo idempotence" {
    const allocator = testing.allocator;

    var pt = PieceTable().init(allocator);
    defer pt.deinit();

    try pt.append(Op.origin, "Hello World\n", 0);
    try pt.append(Op.add, "! What's up?", 11);

    pt.undo();
    pt.undo();
    pt.undo();

    pt.redo();
    pt.redo();
    pt.redo();

    const result = try pt.replay();
    try testing.expect(std.mem.eql(u8, "Hello World! What's up?\n", result));
    allocator.free(result);
}
