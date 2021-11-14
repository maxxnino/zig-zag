const std = @import("std");
const za = @import("zalgebra");
const assert = std.debug.assert;
const testing = std.testing;
const RectInt = @import("rect.zig").RectInt;
const log = std.log.scoped(.grid);
pub const Index = u32;
const node_null = std.math.maxInt(Index);
const Self = @This();
pub const Vec2 = za.Vec2;

/// Stores the number of columns, rows, and cells in the grid.
num_cols: u32,
num_rows: u32,
num_cells: u32,

// Stores the inverse size of a cell.
inv_cells_size: f32,

// Stores the half-size of all elements stored in the grid.
h_size: Vec2,

// Stores the lower-left corner of the grid.
pos: Vec2,

// Stores the size of the grid.
width: u32,
height: u32,
nodes: std.ArrayList(GridElt),
lists: std.ArrayList(IndexLinkList),
free_list: IndexLinkList,

const GridElt = struct {
    /// Stores the next element in the cell.
    next: u32,
    /// Stores the ID of the element. This can be used to associate external
    /// data to the element.
    entity: Index,
    /// Stores the center position of the uniformly-sized element.
    m_pos: Vec2,

    /// Remove a node from the list.
    pub fn removeNext(node: *GridElt, nodes: []GridElt) ?Index {
        if (node.next == node_null) return null;
        const next = node.next;
        node.next = nodes[next].next;
        return next;
    }

    pub fn getNext(self: GridElt) ?Index {
        if (self.next != node_null) {
            return self.next;
        }
        return null;
    }
};

const IndexLinkList = struct {
    first: u32 = node_null,

    /// Insert a new node at the head.
    pub fn prepend(list: *IndexLinkList, nodes: []GridElt, new_node_index: Index) void {
        nodes[new_node_index].next = list.first;
        list.first = new_node_index;
    }

    pub fn getFirst(list: IndexLinkList) ?Index {
        if (list.first != node_null) {
            return list.first;
        }
        return null;
    }

    pub fn popFirst(list: *IndexLinkList, nodes: []GridElt) ?Index {
        if (list.first == node_null) return null;
        const first = list.first;
        list.first = nodes[first].next;
        return first;
    }
};

pub const InitInfo = struct {
};
pub fn init(
    allocator: *std.mem.Allocator,
    position: Vec2,
    half_element_size: f32,
    cell_size: f32,
    num_cols: u32,
    num_rows: u32,
) Self {
    return .{
        .inv_cells_size = 1.0 / cell_size,
        .num_cols = num_cols,
        .num_rows = num_rows,
        .num_cells = num_cols * num_rows,
        .pos = position,
        .width = num_rows * @floatToInt(u32, cell_size),
        .height = num_cols * @floatToInt(u32, cell_size),
        .h_size = Vec2.new(half_element_size, half_element_size),
        .lists = std.ArrayList(IndexLinkList).init(allocator),
        .nodes = std.ArrayList(GridElt).init(allocator),
        .free_list = IndexLinkList{},
    };
}

pub fn deinit(self: *Self) void {
    self.nodes.deinit();
    self.lists.deinit();
}

pub fn insert(self: *Self, entity: Index, pos: Vec2) !void {
    self.ensureInitLists();
    const cell = self.posToCell(pos);
    self.insertToCell(cell, GridElt{
        .next = node_null,
        .entity = entity,
        .m_pos = pos,
    });
}

fn ensureInitLists(self: *Self) void {
    if (self.nodes.items.len != 0) return;
    self.lists.appendNTimes(.{}, self.num_rows * self.num_cols) catch unreachable;
}

pub fn remove(self: *Self, entity: Index, m_pos: Vec2) void {
    const cell = self.posToCell(m_pos);
    self.removeFromCell(cell, entity);
}

pub fn move(self: *Self, entity: Index, from_pos: Vec2, to_pos: Vec2) void {
    var from_cell = self.posToCell(from_pos);
    var to_cell = self.posToCell(to_pos);
    if (from_cell != to_cell) {
        self.removeFromCell(from_cell, entity);
        self.insertToCell(to_cell, GridElt{
            .next = node_null,
            .entity = entity,
            .pos = to_pos,
        });
    }
}

fn insertToCell(self: *Self, cell: Index, elt: GridElt) void {
    var nodes = self.nodes.items;
    const free_node = self.free_list.popFirst(nodes);
    if (free_node) |index| {
        nodes[index] = elt;
        return self.lists.items[cell].prepend(nodes, index);
    }

    const index = @intCast(Index, nodes.len);
    self.nodes.append(elt) catch unreachable;
    self.lists.items[cell].prepend(self.nodes.items, index);
}

fn removeFromCell(self: *Self, cell: Index, entity: Index) void {
    var lists = self.lists.items;
    var nodes = self.nodes.items;
    var index = lists[cell].popFirst(nodes);
    var prev_idx: ?Index = null;
    assert(index != null);
    while (index) |value| {
        if (nodes[value].entity == entity) {
            const removed_index = if (prev_idx) |entry| {
                nodes[entry].removeNext(nodes).?;
            } else value;
            return self.free_list.prepend(nodes, removed_index);
        }
        prev_idx = value;
        index = nodes[value].getNext();
    }

    unreachable;
}

pub fn query(self: *Self, m_pos: Vec2, h_size: Vec2, callback: anytype) void {
    if (!@hasDecl(std.meta.Child(@TypeOf(callback)), "onOverlap")) {
        @compileError("Expect " ++ @typeName(@TypeOf(callback)) ++ " has onCallback function");
    }
    const f_size = h_size.add(self.h_size);
    const begin_x = self.posToGridX(m_pos.x - f_size.x);
    const end_x = self.posToGridX(m_pos.x + f_size.x);
    const end_y = self.posToGridY(m_pos.y + f_size.y);
    var current_y = self.posToGridY(m_pos.y - f_size.y);
    var current_x = begin_x;
    var nodes: []const GridElt = self.nodes.items;
    var lists: []const IndexLinkList = self.lists.items;
    while (current_y <= end_y) : (current_y += 1) {
        while (current_x <= end_x) : (current_x += 1) {
            const cell = self.cellIndex(current_x, current_y);
            var current_idx = lists[cell].getFirst();
            while (current_idx) |value| {
                if (std.math.fabs(m_pos.x - nodes[value].m_pos.x) <= f_size.x and
                    std.math.fabs(m_pos.y - nodes[value].m_pos.y) <= f_size.y)
                {
                    callback.onOverlap(nodes[value].entity);
                }
                current_idx = nodes[value].getNext();
            }
        }
        current_x = begin_x;
    }
}
fn posToCell(self: Self, pos: Vec2) u32 {
    const x = self.posToGridX(pos.x);
    const y = self.posToGridY(pos.y);
    return self.cellIndex(x, y);
}

fn posToGridX(self: Self, x: f32) u32 {
    const local_x = x - self.pos.x;
    return self.localPosToIdx(local_x, self.num_rows);
}

fn posToGridY(self: Self, y: f32) u32 {
    const local_y = y - self.pos.y;
    return self.localPosToIdx(local_y, self.num_cols);
}

fn localPosToIdx(self: Self, value: f32, cells: u32) u32 {
    if (value < 0) return 0;
    return std.math.min(@floatToInt(u32, value * self.inv_cells_size), cells - 1);
}

fn cellIndex(self: Self, grid_x: u32, grid_y: u32) u32 {
    return grid_y * self.num_rows + grid_x;
}

test "cell index" {
    const scale = 4;
    var grid = Self.init(
        testing.allocator,
        Vec2.new(0, 0),
        @intToFloat(f32, scale) / 4,
        scale,
        2,
        2,
    );
    try testing.expectEqual(grid.posToCell(Vec2.new(0 * scale, 0 * scale)), 0);
    try testing.expectEqual(grid.posToCell(Vec2.new(0 * scale, 1 * scale)), 2);
    try testing.expectEqual(grid.posToCell(Vec2.new(1 * scale, 0 * scale)), 1);
    try testing.expectEqual(grid.posToCell(Vec2.new(1 * scale, 1 * scale)), 3);
    try testing.expectEqual(grid.posToCell(Vec2.new(-1 * scale, -1 * scale)), 0);
    try testing.expectEqual(grid.posToCell(Vec2.new(2 * scale, 0 * scale)), 1);
    try testing.expectEqual(grid.posToCell(Vec2.new(0 * scale, 2 * scale)), 2);
    try testing.expectEqual(grid.posToCell(Vec2.new(2 * scale, 2 * scale)), 3);
}

test "Performance\n" {
    const builtin = @import("builtin");
    if(builtin.mode == .Debug){
        return error.SkipZigTest;
    }
    const x = 100;
    const y = 100;
    const size = 4;
    var random = std.rand.Xoshiro256.init(0).random();
    const Entity = std.MultiArrayList(struct {
        entity: u32,
        pos: Vec2,
        half_size: f32,
    });
    const allocator = std.testing.allocator;
    var grid = Self.init(
        testing.allocator,
        Vec2.new(0, 0),
        @intToFloat(f32, size) / 4,
        size,
        x,
        y,
    );
    defer grid.deinit();
    var manager = Entity{};
    defer manager.deinit(allocator);
    try manager.setCapacity(allocator, x * y);
    {
        var entity: u32 = 0;
        while (entity < x * y) : (entity += 1) {
            const x_pos = random.float(f32) * @intToFloat(f32, x * y * size * size);
            const y_pos = random.float(f32) * @intToFloat(f32, x * y * size * size);
            const pos = Vec2.new(x_pos, y_pos);
            try manager.append(allocator, .{
                .entity = entity,
                .pos = pos,
                .half_size = 1.0,
            });
        }
    }

    var slice = manager.slice();
    var entities = slice.items(.entity);
    var position = slice.items(.pos);
    {
        var timer = try std.time.Timer.start();

        var index: u32 = 0;
        while (index < slice.len) : (index += 1) {
            grid.insert(entities[index], position[index]) catch unreachable;
        }
        const time_0 = timer.read();
        std.debug.print("add {} entity take {}ms\n", .{ x * y, time_0 / std.time.ns_per_ms });
    }

    {
        const QueryCallback = struct {
            total: u32 = 0,
            pub fn onOverlap(self: *@This(), entity: u32) void {
                _ = entity;
                self.total += 1;
            }
        };
        var callback = QueryCallback{};
        var entity: u32 = 0;
        const esize = Vec2.new(size / 4, size / 4);
        var timer = try std.time.Timer.start();
        while (entity < slice.len) : (entity += 1) {
            grid.query(position[entity], esize, &callback);
        }
        const time_0 = timer.read();
        std.debug.print("callback query {} entity, with {} callback take {}ms\n", .{
            x * y,
            callback.total,
            time_0 / std.time.ns_per_ms,
        });
    }
}
