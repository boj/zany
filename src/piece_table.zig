const std = @import("std");
const testing = std.testing;

pub fn PieceTable() type {
    return struct {
        const Self = @This();

        root: ?*const Piece = null,

        const Piece = struct {
            next: ?*Piece,
            data: []const u8,
            start_idx: u32,
        };

        fn initPiece(data: []const u8) Piece {
            return Piece{
                .next = null,
                .data = data,
                .start_idx = 0,
            };
        }

        pub fn initPieceTable(self: *Self, data: []const u8) !void {
            const init = initPiece(data);
            self.root = &init;
        }
    };
}

const PieceTableTest = PieceTable();

test "PieceTable" {
    var pt = PieceTableTest{};
    try pt.initPieceTable("bojo");

    if (pt.root != null) {
        try testing.expectEqual(pt.root.?.data, "bojo");
    }
}
