const std = @import("std");
const vaxis = @import("vaxis");
const piece_table = @import("piece_table.zig");
const Cell = vaxis.Cell;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

const log = std.log.scoped(.main);
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memeory leak", .{});
        }
    }
    const alloc = gpa.allocator();

    const PieceTable = piece_table.PieceTable();
    var pt = PieceTable{ .pieces = undefined };
    try pt.initPieceTable(alloc, "bojo");

    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc, tty.anyWriter());

    // event loop
    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    var color_idx: u8 = 0;
    const msg = "Hello, world!";

    while (true) {
        const event = loop.nextEvent();
        log.debug("event: {}", .{event});
        switch (event) {
            .key_press => |key| {
                color_idx = switch (color_idx) {
                    255 => 0,
                    else => color_idx + 1,
                };
                if (key.codepoint == 'c' and key.mods.ctrl) {
                    break;
                }
            },
            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
            else => {},
        }
        const win = vx.window();
        win.clear();

        const child = win.initChild(win.width / 2 - msg.len / 2, win.height / 2, .expand, .expand);
        for (msg, 0..) |_, i| {
            const cell: Cell = .{
                .char = .{ .grapheme = msg[i .. i + 1] },
                .style = .{
                    .fg = .{ .index = color_idx },
                },
            };
            child.writeCell(i, 0, cell);
        }

        try vx.render(tty.anyWriter());
    }
}
