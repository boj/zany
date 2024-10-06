const std = @import("std");
const testing = std.testing;
const SinglyLinkedList = std.SinglyLinkedList;

// Each subsequent command builds off the representation
// of the culmination of everything prior. In a way this
// is more like append-only Event Sourcing where the result
// is the sum of all prior commands.
//
// Piece { .op, .string, .start, .length }
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

        root: SinglyLinkedList(Piece) = SinglyLinkedList(Piece){},

        const Piece = struct {
            op: Op,
            string: []const u8,
            start: usize,
            length: usize,
        };

        pub fn init(self: *Self, alloc: std.mem.Allocator, string: []const u8) !void {
            try self.append(alloc, Op.origin, string, 0);
        }

        pub fn len(self: *Self) usize {
            return self.root.len();
        }

        pub fn append(self: *Self, alloc: std.mem.Allocator, op: Op, string: []const u8, s: usize) !void {
            const Node = std.SinglyLinkedList(Piece).Node;
            var node_ptr = try alloc.create(Node);
            node_ptr.data = Piece{
                .op = op,
                .string = string,
                .start = s,
                .length = string.len,
            };
            self.root.prepend(node_ptr);
        }

        pub fn replay(self: *Self, alloc: std.mem.Allocator) ![]const u8 {
            var origin = std.ArrayList(u8).init(alloc);
            defer origin.deinit();

            std.SinglyLinkedList(Piece).Node.reverse(&self.root.first);
            var it = self.root.first;
            while (it) |node| {
                switch (node.data.op) {
                    Op.origin => try origin.appendSlice(node.data.string),
                    Op.add => try origin.insertSlice(node.data.start, node.data.string),
                    Op.delete => {
                        for (0..node.data.length) |_| {
                            _ = origin.orderedRemove(node.data.start);
                        }
                    },
                }
                it = it.?.next;
            }
            std.SinglyLinkedList(Piece).Node.reverse(&self.root.first);
            return origin.toOwnedSlice();
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            var it = self.root.first;
            while (it) |node| : (it = it.?.next) {
                alloc.destroy(node);
            }
        }
    };
}

const PieceTableTest = PieceTable();

test "PieceTable: init, append, len, replay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var pt = PieceTableTest{};
    defer pt.deinit(alloc);

    try pt.init(alloc, "Hello World\n");
    try testing.expectEqual(pt.root.first.?.data.string, "Hello World\n");
    try testing.expect(pt.len() == 1);

    try pt.append(alloc, Op.add, "There ", 6);
    try testing.expect(pt.len() == 2);
    var result = try pt.replay(alloc);
    try testing.expect(std.mem.eql(u8, "Hello There World\n", result));

    try pt.append(alloc, Op.delete, "llo The", 2);
    try testing.expect(pt.len() == 3);
    result = try pt.replay(alloc);
    try testing.expect(std.mem.eql(u8, "Here World\n", result));

    try pt.append(alloc, Op.delete, "Here", 0);
    try pt.append(alloc, Op.add, "Sup", 0);
    try testing.expect(pt.len() == 5);

    result = try pt.replay(alloc);
    try testing.expect(std.mem.eql(u8, "Sup World\n", result));
}
