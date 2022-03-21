const std = @import("std");
const basic_type = @import("basic_type.zig");
const za = @import("zalgebra");
const assert = std.debug.assert;
const testing = std.testing;
const log = std.log.scoped(.grid);
const IndexLinkList = @import("IndexLinkList.zig");

const node_null = basic_type.node_null;
const Index = basic_type.Index;
const Grid = @This();
const Vec2 = basic_type.Vec2;
const Node = struct {
    /// Stores the next element in the cell.
    next: Index,
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

const NodeList = std.MultiArrayList(Node);
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
nodes: NodeList.Slice,
node_list: NodeList,
lists: std.ArrayList(IndexLinkList),
free_list: IndexLinkList,
allocator: std.mem.Allocator,

pub const InitInfo = struct {};
pub fn init(
    allocator: std.mem.Allocator,
    position: Vec2,
    h_size: Vec2,
    cell_size: f32,
    num_cols: u32,
    num_rows: u32,
) Grid {
    var node_list = NodeList{};
    return .{
        .inv_cells_size = 1.0 / cell_size,
        .num_cols = num_cols,
        .num_rows = num_rows,
        .num_cells = num_cols * num_rows,
        .pos = position,
        .width = num_rows * @floatToInt(u32, @floor(cell_size)),
        .height = num_cols * @floatToInt(u32, @floor(cell_size)),
        .h_size = h_size,
        .lists = std.ArrayList(IndexLinkList).init(allocator),
        .nodes = node_list.slice(),
        .node_list = node_list,
        .free_list = IndexLinkList{},
        .allocator = allocator,
    };
}

pub fn deinit(self: *Grid) void {
    self.node_list.deinit(self.allocator);
    self.lists.deinit();
}

pub fn insert(self: *Grid, entity: Index, pos: Vec2) void {
    self.ensureInitLists();
    const cell = self.posToCell(pos);
    self.insertToCell(cell, Node{
        .next = node_null,
        .entity = entity,
        .m_pos = pos,
    });
}

fn ensureInitLists(self: *Grid) void {
    if (self.lists.items.len != 0) return;
    self.lists.appendNTimes(.{}, self.num_rows * self.num_cols) catch unreachable;
}

pub fn remove(self: *Grid, entity: Index, m_pos: Vec2) void {
    const cell = self.posToCell(m_pos);
    self.removeFromCell(cell, entity);
}

pub fn move(self: *Grid, entity: Index, from_pos: Vec2, to_pos: Vec2) void {
    var from_cell = self.posToCell(from_pos);
    var to_cell = self.posToCell(to_pos);
    if (from_cell == to_cell) return;
    self.removeFromCell(from_cell, entity);
    self.insertToCell(to_cell, Node{
        .next = node_null,
        .entity = entity,
        .m_pos = to_pos,
    });
}

fn insertToCell(self: *Grid, cell: Index, elt: Node) void {
    var next = self.nodes.items(.next);
    const free_node = self.free_list.popFirst(next);
    if (free_node) |index| {
        self.node_list.set(index, elt);
        return self.lists.items[cell].prepend(index, next);
    }

    const index = @intCast(Index, self.nodes.len);
    self.node_list.append(self.allocator, elt) catch unreachable;
    self.nodes = self.node_list.slice();
    self.lists.items[cell].prepend(index, self.nodes.items(.next));
}

fn removeFromCell(self: *Grid, cell: Index, entity: Index) void {
    var lists = self.lists.items;
    var next = self.nodes.items(.next);
    var entities = self.nodes.items(.entity);
    var node = lists[cell].getFirst().?;
    var prev_idx: ?Index = null;
    while (entities[node] != entity) {
        prev_idx = node;
        node = Node.getNext(node, next).?;
    }
    if (prev_idx) |prev| {
        next[prev] = next[node];
    } else {
        lists[cell].first = next[node];
    }
}

pub fn query(grid: *Grid, m_pos: Vec2, h_size: Vec2, entity: anytype, callback: anytype) void {
    const CallBackType = std.meta.Child(@TypeOf(callback));
    if (!@hasDecl(CallBackType, "onOverlap")) {
        @compileError("Expect " ++ @typeName(@TypeOf(callback)) ++ " has onCallback function");
    }

    const f_size = h_size.add(grid.h_size);
    const begin_bound = grid.posToGrid(m_pos.sub(h_size));
    const end_bound = grid.posToGrid(m_pos.add(h_size));

    // const begin_x = grid.posToGridXClamp(left_bound.x());
    const begin_x = begin_bound.x();
    // const end_x = grid.posToGridXClamp(right_bound.x());
    const end_x = end_bound.x();
    // const end_y = grid.posToGridYClamp(right_bound.y());
    const end_y = end_bound.y();
    // var current_y = grid.posToGridYClamp(left_bound.y());
    var current_y = begin_bound.x();

    const lists = grid.lists.items;
    const next = grid.nodes.items(.next);
    const entities = grid.nodes.items(.entity);
    const positions = grid.nodes.items(.m_pos);
    while (current_y <= end_y) : (current_y += 1) {
        var current_x = begin_x;
        while (current_x <= end_x) : (current_x += 1) {
            const cell = grid.cellIndex(current_x, current_y);
            var current_idx = lists[cell].getFirst();
            while (current_idx) |value| : (current_idx = Node.getNext(value, next)) {
                if (@TypeOf(entity) == u32) {
                    if (entities[value] == entity) continue;
                }
                const distant = m_pos.sub(positions[value]);
                if (@reduce(.And, @fabs(distant.data) < f_size.data)) {
                    callback.onOverlap(entity, entities[value]);
                }
            }
        }
    }
}

fn posToCell(self: Grid, pos: Vec2) u32 {
    const idx = self.posToGridUnSafe(pos);
    assert(@reduce(.And, idx.data < @Vector(2, u32){ self.num_rows, self.num_cols }));
    return self.cellIndex(idx.x(), idx.y());
}

fn posToGridUnSafe(self: Grid, pos: Vec2) za.GenericVector(2, u32) {
    const local = (Vec2{ .data = @floor(pos.data) }).sub(self.pos);
    return local.scale(self.inv_cells_size).cast(u32);
}

fn posToGrid(self: Grid, pos: Vec2) za.GenericVector(2, u32) {
    const idx = self.posToGridUnSafe(pos);
    return .{ .data = @maximum(
        @minimum(idx.data, @Vector(2, u32){ self.num_rows - 1, self.num_rows - 1 }),
        @splat(2, @as(u32, 0)),
    ) };
}

fn cellIndex(self: Grid, grid_x: u32, grid_y: u32) u32 {
    return grid_x * self.num_rows + grid_y;
}

test "Performance" {
    std.debug.print("\n", .{});
    const x = 100;
    const y = 100;
    const size = 4;
    const h_size = @intToFloat(f32, size) / 4;
    const total = x * y * 4;
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
        Vec2.new(h_size, h_size),
        size,
        x,
        y,
    );
    defer grid.deinit();
    var manager = Entity{};
    defer manager.deinit(allocator);
    try manager.ensureTotalCapacity(allocator, total);
    {
        var entity: u32 = 0;
        while (entity < total) : (entity += 1) {
            const x_pos = random.float(f32) * @intToFloat(f32, x * size);
            const y_pos = random.float(f32) * @intToFloat(f32, y * size);
            const pos = Vec2.new(x_pos, y_pos);
            manager.appendAssumeCapacity(.{
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
            grid.insert(entities[index], position[index]);
        }
        const time_0 = timer.read();
        std.debug.print("add {} entity take {}ms\n", .{ total, time_0 / std.time.ns_per_ms });
    }
    const total_loop = 20;
    var current_loop: u32 = 0;
    var move_time: u64 = 0;
    var query_time: u64 = 0;
    while (current_loop < total_loop) : (current_loop += 1) {
        {
            var timer = try std.time.Timer.start();
            var entity: u32 = 0;
            while (entity < total) : (entity += 1) {
                const x_pos = random.float(f32) * @intToFloat(f32, x * size);
                const y_pos = random.float(f32) * @intToFloat(f32, y * size);
                const pos = Vec2.new(x_pos, y_pos);
                grid.move(entities[entity], position[entity], pos);
                position[entity] = pos;
            }
            const time_0 = timer.read();
            move_time += time_0 / std.time.ns_per_ms;
        }
        {
            const QueryCallback = struct {
                total: u32 = 0,
                pub fn onOverlap(self: *@This(), payload: u32, entity: u32) void {
                    if (payload >= entity) return;
                    self.total += 1;
                }
            };
            var callback = QueryCallback{};
            var entity: u32 = 0;
            const esize = Vec2.new(size / 4, size / 4);
            var timer = try std.time.Timer.start();
            while (entity < slice.len) : (entity += 1) {
                grid.query(position[entity], esize, entities[entity], &callback);
            }
            const time_0 = timer.read();
            query_time += time_0 / std.time.ns_per_ms;
        }
    }
    std.debug.print("move take {}ms\n", .{move_time / total_loop});
    std.debug.print("query take {}ms\n", .{query_time / total_loop});
}
