const std = @import("std");
const za = @import("zalgebra");
const assert = std.debug.assert;
const testing = std.testing;
const RectInt = @import("rect.zig").RectInt;

pub const Index = u32;
const IndexLinkList = struct {
    const Node = struct {
        const node_null = std.math.maxInt(Index);
        next: Index = node_null,

        /// Remove a node from the list.
        ///
        /// Arguments:
        ///     node: Index to the node to be removed.
        /// Returns:
        ///     Index removed
        pub fn removeNext(node: *Node, nodes: []Node) ?Index {
            if (node.next == node_null) return null;
            const next = node.next;
            node.next = nodes[next].next;
            return next;
        }

        /// Iterate over each next node, returning the count of all nodes except the starting one.
        /// This operation is O(N).
        pub fn countChildren(node: Node, nodes: []const Node) u32 {
            var count: usize = 0;
            var it = node.next;
            while (it != node_null) : (it = nodes[it].next) {
                count += 1;
            }
            return count;
        }

        pub fn getNext(self: Node) ?Index {
            if (self.next != node_null) {
                return self.next;
            }
            return null;
        }
    };
    first: u32 = Node.node_null,
    const Self = @This();

    /// Insert a new node at the head.
    pub fn prepend(list: *Self, nodes: []Node, new_node_index: Index) void {
        nodes[new_node_index].next = list.first;
        list.first = new_node_index;
    }

    pub fn getFirst(list: Self) ?Index {
        if (list.first != Node.node_null) {
            return list.first;
        }
        return null;
    }

    pub fn popFirst(list: *Self, nodes: []Node) ?Index {
        if (list.first == Node.node_null) return null;
        const first = list.first;
        list.first = nodes[first].next;
        return first;
    }
};
/// node_size: 
pub fn Grid(comptime T: type, comptime node_size: u32) type {
    return struct {
        const Self = @This();
        pub const Vec2 = za.Vector2(T);
        const NodeList = std.MultiArrayList(struct {
            node: IndexLinkList.Node,
            entity: Index,
        });
        const Iterator = struct {
            frame: @Frame(query),
            current_entity: ?Index,
            grid: Self,

            pub fn next(it: *Iterator) ?Index {
                if (it.current_entity) |value| {
                    resume it.frame;
                    return value;
                }
                return null;
            }
            pub fn refresh(it: *Iterator, aabb: RectInt) void {
                const btm_left = aabb.lower_bound.sub(Vec2.new(max_entity_size, max_entity_size));
                const top_right = aabb.upper_bound.add(Vec2.new(max_entity_size, max_entity_size));
                it.frame = async it.query(btm_left, top_right);
            }

            fn query(it: *Iterator, btm_left: Vec2, top_right: Vec2) void {
                const begin_x = it.grid.posToGridX(btm_left);
                const end_x = it.grid.posToGridX(top_right);
                const end_y = it.grid.posToGridY(top_right);
                var current_y = it.grid.posToGridY(btm_left);
                var current_x = begin_x;
                var slice = it.grid.nodes.slice();
                var nodes = slice.items(.node);
                var entities = slice.items(.entity);
                var lists = it.grid.lists.items;
                while (current_y <= end_y) : (current_y += 1) {
                    while (current_x <= end_x) : (current_x += 1) {
                        const cell = it.grid.cellIndex(current_x, current_y);
                        const first = lists[cell].getFirst();
                        if (first) |value| {
                            var current_node = value;
                            it.current_entity = entities[current_node];
                            suspend {}
                            while (nodes[current_node].getNext()) |entry| {
                                current_node = entry;
                                it.current_entity = entities[current_node];
                                suspend {}
                            }
                        }
                    }
                    current_x = begin_x;
                }
                it.current_entity = null;
            }
        };

        const max_entity_size = node_size / 4;
        allocator: *std.mem.Allocator,
        total_entity: u32,
        pos: Vec2,
        row: u32,
        column: u32,

        // nodes and entities use the same index
        nodes: NodeList,
        lists: std.ArrayList(IndexLinkList),
        free_list: IndexLinkList,
        /// size: grid size
        /// pos: gird world pos
        pub fn init(allocator: *std.mem.Allocator, row: u32, column: u32, pos: Vec2) Self {
            return .{
                .allocator = allocator,
                .total_entity = 0,
                .row = row,
                .column = column,
                .pos = pos,
                .nodes = NodeList{},
                .lists = std.ArrayList(IndexLinkList).init(allocator),
                .free_list = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit(self.allocator);
            self.lists.deinit();
        }

        pub fn insert(self: *Self, entity: Index, pos: Vec2) !void {
            self.ensureInitLists();
            const cell = self.posToCell(pos);
            self.insertToCell(cell, entity);
        }

        pub fn remove(self: *Self, entity: Index, pos: Vec2) void {
            const cell = self.posToCell(pos);
            self.removeFromCell(cell, entity);
        }

        pub fn move(self: *Self, entity: Index, from_pos: Vec2, to_pos: Vec2) void {
            var from_cell = self.posToCell(from_pos);
            var to_cell = self.posToCell(to_pos);
            if (from_cell != to_cell) {
                self.removeFromCell(from_cell, entity);
                self.insertToCell(to_cell, entity);
            }
        }

        pub fn queryIterator(grid: Self) Iterator {
            return .{
                .frame = undefined,
                .current_entity = null,
                .grid = grid,
            };
        }

        fn insertToCell(self: *Self, cell: Index, entity: Index) void {
            std.debug.print("Insert: e: {}, cell: {}\n", .{ entity, cell });
            var nodes = self.nodes.items(.node);
            const free_node = self.free_list.popFirst(nodes);
            if (free_node) |index| {
                self.nodes.set(index, .{
                    .node = .{},
                    .entity = entity,
                });
                return self.lists.items[cell].prepend(nodes, index);
            }

            const index = @intCast(Index, self.nodes.len);
            self.nodes.append(self.allocator, .{
                .node = .{},
                .entity = entity,
            }) catch unreachable;
            self.lists.items[cell].prepend(self.nodes.items(.node), index);
        }

        fn removeFromCell(self: *Self, cell: Index, entity: Index) void {
            std.debug.print("Remove: e: {}, cell: {}\n", .{ entity, cell });
            var lists = self.lists.items;
            var slice = self.nodes.slice();
            var entities = slice.items(.entity);
            var nodes = slice.items(.node);
            var index = lists[cell].getFirst();
            var prev_idx: ?Index = null;
            assert(index != null);
            if (index) |value| {
                if (entities[value] == entity) {
                    const removed_index = lists[cell].popFirst(nodes).?;
                    return self.free_list.prepend(nodes, removed_index);
                }
                prev_idx = value;
                index = nodes[value].getNext();
            }

            while (index) |value| {
                if (entities[value] == entity) {
                    const removed_index = nodes[prev_idx.?].removeNext(nodes).?;
                    return self.free_list.prepend(nodes, removed_index);
                }
                prev_idx = value;
                index = nodes[value].getNext();
            }

            unreachable;
        }

        fn ensureInitLists(self: *Self) void {
            if (self.nodes.len != 0) return;
            self.lists.appendNTimes(.{}, self.row * self.column) catch unreachable;
        }

        fn posToCell(self: Self, pos: Vec2) u32 {
            const local_pos = pos.sub(self.pos);
            // TODO: clamp pos inside grid or remove if outside grid
            const x = self.localPosToGridX(local_pos);
            const y = self.localPosToGridY(local_pos);
            return self.cellIndex(x, y);
        }

        fn posToGridX(self: Self, pos: Vec2) u32 {
            const local_pos = pos.sub(self.pos);
            return self.localPosToGridX(local_pos);
        }

        fn posToGridY(self: Self, pos: Vec2) u32 {
            const local_pos = pos.sub(self.pos);
            return self.localPosToGridY(local_pos);
        }

        fn localPosToGridX(self: Self, pos: Vec2) u32 {
            if (pos.x < 0) return 0;
            return std.math.min(@intCast(u32, pos.x) / node_size, self.row - 1);
        }

        fn localPosToGridY(self: Self, pos: Vec2) u32 {
            if (pos.y < 0) return 0;
            return std.math.min(@intCast(u32, pos.y) / node_size, self.column - 1);
        }

        fn cellIndex(self: Self, grid_x: u32, grid_y: u32) u32 {
            return grid_y * self.row + grid_x;
        }
    };
}

test "cell index" {
    const scale = 4;
    const GridInt = Grid(i32, scale);
    const Vec2 = GridInt.Vec2;
    var grid = GridInt.init(testing.allocator, 2, 2, Vec2.new(0, 0));
    try testing.expectEqual(grid.posToCell(Vec2.new(0 * scale, 0 * scale)), 0);
    try testing.expectEqual(grid.posToCell(Vec2.new(0 * scale, 1 * scale)), 2);
    try testing.expectEqual(grid.posToCell(Vec2.new(1 * scale, 0 * scale)), 1);
    try testing.expectEqual(grid.posToCell(Vec2.new(1 * scale, 1 * scale)), 3);
    try testing.expectEqual(grid.posToCell(Vec2.new(-1 * scale, -1 * scale)), 0);
    try testing.expectEqual(grid.posToCell(Vec2.new(2 * scale, 0 * scale)), 1);
    try testing.expectEqual(grid.posToCell(Vec2.new(0 * scale, 2 * scale)), 2);
    try testing.expectEqual(grid.posToCell(Vec2.new(2 * scale, 2 * scale)), 3);
}

test "add/remove" {
        std.debug.print("\n", .{});
        const GridInt = Grid(i32, 1);
        const Vec2 = GridInt.Vec2;
        const Entity = std.MultiArrayList(struct {
            entity: Index,
            pos: Vec2,
        });
        const allocator = std.testing.allocator;
        var grid = GridInt.init(
            allocator,
            20,
            20,
            GridInt.Vec2.new(0, 0),
        );
        defer grid.deinit();
        var manager = Entity{};
        defer manager.deinit(allocator);
        try manager.append(allocator, .{ .entity = 0, .pos = Vec2.new(0, 0) });
        try manager.append(allocator, .{ .entity = 1, .pos = Vec2.new(1, 0) });
        try manager.append(allocator, .{ .entity = 2, .pos = Vec2.new(0, 1) });
        try manager.append(allocator, .{ .entity = 3, .pos = Vec2.new(4, 4) });
        try manager.append(allocator, .{ .entity = 4, .pos = Vec2.new(5, 5) });
        try manager.append(allocator, .{ .entity = 5, .pos = Vec2.new(5, 0) });

        var slice = manager.slice();
        var entities = slice.items(.entity);
        var position = slice.items(.pos);
        var index: u32 = 0;
        while (index < slice.len) : (index += 1) {
            grid.insert(entities[index], position[index]) catch unreachable;
        }
        var it = grid.queryIterator();

        std.debug.print("query at {{{},{}}}-{{{},{}}}\n", .{ 0, 0, 5, 5 });
        it.refresh(RectInt.new(Vec2.new(0, 0), Vec2.new(5, 5)));
        while (it.next()) |value| {
            std.debug.print("query: {}\n", .{value});
        }
        index = 0;
        grid.move(entities[index], position[index], Vec2.new(2, 2));

        std.debug.print("query at {{{},{}}}-{{{},{}}}\n", .{ 0, 0, 3, 3 });
        it.refresh(RectInt.new(Vec2.new(0, 0), Vec2.new(3, 3)));
        while (it.next()) |value| {
            std.debug.print("query: {}\n", .{value});
        }
        index = 2;
        grid.remove(entities[index], position[index]);
        index = 4;
        grid.remove(entities[index], position[index]);

        it.refresh(RectInt.new(Vec2.new(0, 0), Vec2.new(5, 5)));

        std.debug.print("query at {{{},{}}}-{{{},{}}}\n", .{ 0, 0, 5, 5 });
        while (it.next()) |value| {
            std.debug.print("query: {}\n", .{value});
        }
        index = 2;
        grid.insert(entities[index], position[index]) catch unreachable;
        index = 4;
        grid.insert(entities[index], position[index]) catch unreachable;

        it.refresh(RectInt.new(Vec2.new(0, 0), Vec2.new(5, 5)));

        std.debug.print("query at {{{},{}}}-{{{},{}}}\n", .{ 0, 0, 5, 5 });
        while (it.next()) |value| {
            std.debug.print("query: {}\n", .{value});
        }
}
