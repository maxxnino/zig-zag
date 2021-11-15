const std = @import("std");
const basic_type = @import("basic_type.zig");
const assert = std.debug.assert;
const testing = std.testing;
const log = std.log.scoped(.grid);

const Index = u32;
const Grid = @This();
const Vec2 = basic_type.Vec2;
const node_null = std.math.maxInt(Index);
const Node = struct {
    /// Stores the next element in the cell.
    next: u32 = node_null,
    /// Stores the ID of the element. This can be used to associate external
    /// data to the element.
    entity: Index,
    /// Stores the center position of the uniformly-sized element.
    m_pos: Vec2,

    /// Remove a node from the list.
    pub fn removeNext(node: Index, next: []Index) ?Index {
        const next_node = next[node];
        if (next_node == node_null) return null;
        next[node] = next[next_node];
        return next_node;
    }

    pub fn getNext(node: Index, next: []Index) ?Index {
        const next_node = next[node];
        return if (next_node != node_null) next_node else null;
    }
};

const IndexLinkList = struct {
    first: u32 = node_null,

    /// Insert a new node at the head.
    pub fn prepend(list: *IndexLinkList, node: Index, next: []Index) void {
        next[node] = list.first;
        list.first = node;
    }

    pub fn getFirst(list: IndexLinkList) ?Index {
        return if (list.first != node_null) list.first else null;
    }

    pub fn popFirst(list: *IndexLinkList, next: []Index) ?Index {
        if (list.first == node_null) return null;
        const first = list.first;
        list.first = next[first];
        return first;
    }
};

const Row = struct {
    const NodeList = std.MultiArrayList(Node);
    nodes: NodeList.Slice,
    node_list: NodeList,
    lists: std.ArrayList(IndexLinkList),
    free_list: IndexLinkList,
    allocator: *std.mem.Allocator,
    total: u32 = 0,

    fn init(allocator: *std.mem.Allocator) Row {
        var node_list = NodeList{};
        return .{
            .lists = std.ArrayList(IndexLinkList).init(allocator),
            .nodes = node_list.slice(),
            .node_list = node_list,
            .free_list = IndexLinkList{},
            .allocator = allocator,
        };
    }

    fn insertToCell(self: *Row, cell_x: Index, elt: Node) void {
        self.total += 1;
        var next = self.nodes.items(.next);
        const free_node = self.free_list.popFirst(next);
        if (free_node) |index| {
            self.node_list.set(index, elt);
            return self.lists.items[cell_x].prepend(index, next);
        }

        const index = @intCast(Index, self.nodes.len);
        self.node_list.append(self.allocator, elt) catch unreachable;
        self.nodes = self.node_list.slice();
        self.lists.items[cell_x].prepend(index, self.nodes.items(.next));
    }

    fn removeFromCell(self: *Row, cell_x: Index, entity: Index) void {
        self.total -= 1;
        var lists = self.lists.items;
        var next = self.nodes.items(.next);
        var entities = self.nodes.items(.entity);
        var index = lists[cell_x].popFirst(next);
        var prev_idx: ?Index = null;
        assert(index != null);
        while (index) |value| {
            if (entities[value] == entity) {
                const removed_index = if (prev_idx) |entry| {
                    Node.removeNext(entry, next).?;
                } else value;
                return self.free_list.prepend(removed_index, next);
            }
            prev_idx = value;
            index = Node.getNext(value, next);
        }

        unreachable;
    }

    fn ensureInitLists(self: *Row, num_cols: u32) void {
        if (self.lists.items.len != 0) return;
        self.lists.ensureTotalCapacity(num_cols + 1) catch unreachable;
        self.lists.appendNTimesAssumeCapacity(.{}, num_cols + 1);
    }

    fn query(row: Row, begin_x: u32, end_x: u32, m_pos: Vec2, f_size: Vec2, entity: u32, callback: anytype) void {
        if (!@hasDecl(std.meta.Child(@TypeOf(callback)), "onOverlap")) {
            @compileError("Expect " ++ @typeName(@TypeOf(callback)) ++ " has onCallback function");
        }
        // _ = entity;
        if (row.total == 0) return;
        const lists = row.lists.items;
        const next = row.nodes.items(.next);
        const entities = row.nodes.items(.entity);
        const positions = row.nodes.items(.m_pos);
        var current_x = begin_x;
        while (current_x <= end_x) : (current_x += 1) {
            var current_idx = lists[current_x].getFirst();
            while (current_idx) |value| {
                if (entities[value] != entity and
                    std.math.fabs(m_pos.x - positions[value].x) <= f_size.x and
                    std.math.fabs(m_pos.y - positions[value].y) <= f_size.y)
                {
                    callback.onOverlap(entities[value]);
                }
                current_idx = Node.getNext(value, next);
            }
        }
    }

    fn deinit(self: *Row) void {
        self.node_list.deinit(self.allocator);
        self.lists.deinit();
    }
};
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
rows: std.ArrayList(Row),
allocator: *std.mem.Allocator,

pub const InitInfo = struct {};
pub fn init(
    allocator: *std.mem.Allocator,
    position: Vec2,
    half_element_size: f32,
    cell_size: f32,
    num_cols: u32,
    num_rows: u32,
) Grid {
    var rows = std.ArrayList(Row).initCapacity(allocator, num_rows) catch unreachable;
    rows.appendNTimesAssumeCapacity(Row.init(allocator), num_rows);
    return .{
        .inv_cells_size = 1.0 / cell_size,
        .num_cols = num_cols,
        .num_rows = num_rows,
        .num_cells = num_cols * num_rows,
        .pos = position,
        .width = num_rows * @floatToInt(u32, cell_size),
        .height = num_cols * @floatToInt(u32, cell_size),
        .h_size = Vec2.new(half_element_size, half_element_size),
        .rows = rows,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Grid) void {
    for (self.rows.items) |*row| {
        row.deinit();
    }
    self.rows.deinit();
}

pub fn insert(self: *Grid, entity: Index, pos: Vec2) !void {
    const cell_y = self.posToGridY(pos);
    var row = &self.rows.items[cell_y];
    row.ensureInitLists(self.num_cols);

    const cell_x = self.posToGridX(pos);
    row.insertToCell(cell_x, Node{
        .entity = entity,
        .m_pos = pos,
    });
}

pub fn remove(self: *Grid, entity: Index, m_pos: Vec2) void {
    const cell_y = self.posToGridY(m_pos);
    const cell_x = self.posToGridX(m_pos);
    self.rows.items[cell_y].removeFromCell(cell_x, entity);
}

pub fn move(self: *Grid, entity: Index, from_pos: Vec2, to_pos: Vec2) void {
    var from_cell_y = self.posToGridY(from_pos);
    var to_cell_y = self.posToGridY(to_pos);
    var from_cell_x = self.posToGridX(from_pos);
    var to_cell_x = self.posToGridX(to_pos);
    if (from_cell_x != to_cell_x or from_cell_y != from_cell_y) {
        var rows = self.rows.items;
        rows[from_cell_y].removeFromCell(from_cell_x, entity);
        rows[to_cell_y].ensureInitLists(self.num_cols);
        rows[to_cell_y].insertToCell(to_cell_x, Node{
            .entity = entity,
            .pos = to_pos,
        });
    }
}

pub fn query(grid: *Grid, m_pos: Vec2, h_size: Vec2, entity: u32, callback: anytype) void {
    const f_size = h_size.add(grid.h_size);
    const extend_left = m_pos.sub(f_size);
    const extend_right = m_pos.add(f_size);
    const begin_x = grid.posToGridX(extend_left);
    const end_x = grid.posToGridX(extend_right);
    const end_y = grid.posToGridY(extend_right);
    var current_y = grid.posToGridY(extend_left);
    var rows = grid.rows.items;
    while (current_y <= end_y) : (current_y += 1) {
        rows[current_y].query(begin_x, end_x, m_pos, f_size, entity, callback);
    }
}

fn posToCell(self: Grid, pos: Vec2) u32 {
    const x = self.posToGridX(pos);
    const y = self.posToGridY(pos);
    return self.cellIndex(x, y);
}

fn posToGridX(self: Grid, pos: Vec2) u32 {
    const local_x = pos.x - self.pos.x;
    return self.localPosToIdx(local_x, self.num_rows);
}

fn posToGridY(self: Grid, pos: Vec2) u32 {
    const local_y = pos.y - self.pos.y;
    return self.localPosToIdx(local_y, self.num_cols);
}

fn localPosToIdx(self: Grid, value: f32, cells: u32) u32 {
    if (value < 0) return 0;
    return std.math.min(@floatToInt(u32, value * self.inv_cells_size), cells - 1);
}

fn cellIndex(self: Grid, grid_x: u32, grid_y: u32) u32 {
    return grid_y * self.num_rows + grid_x;
}

test "cell index" {
    const scale = 4;
    var grid = Grid.init(
        testing.allocator,
        Vec2.new(0, 0),
        @intToFloat(f32, scale) / 4,
        scale,
        2,
        2,
    );
    defer grid.deinit();
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
    // const builtin = @import("builtin");
    // if (builtin.mode == .Debug) {
    //     return error.SkipZigTest;
    // }
    const x = 40;
    const y = 40;
    const size = 4;
    const total = 20 * 20;
    var random = std.rand.Xoshiro256.init(0).random();
    const Entity = std.MultiArrayList(struct {
        entity: u32,
        pos: Vec2,
        half_size: f32,
    });
    const allocator = std.testing.allocator;
    var grid = Grid.init(
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
        while (entity < total) : (entity += 1) {
            const x_pos = random.float(f32) * @intToFloat(f32, x * y * size * size);
            const y_pos = random.float(f32) * @intToFloat(f32, x * y * size * size);
            const pos = Vec2.new(x_pos, y_pos);
            try manager.append(allocator, .{
                .entity = entity,
                .pos = pos,
                .half_size = 1.0,
            });
        }
        try manager.append(allocator, .{
            .entity = entity + 1,
            .pos = Vec2.new(1, 1),
            .half_size = 1.0,
        });
        try manager.append(allocator, .{
            .entity = entity + 2,
            .pos = Vec2.new(1, 1),
            .half_size = 1.0,
        });
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
            grid.query(position[entity], esize, entity, &callback);
        }
        const time_0 = timer.read();
        std.debug.print("callback query {} entity, with {} callback take {}ms\n", .{
            total,
            callback.total,
            time_0 / std.time.ns_per_ms,
        });
    }
}
