const std = @import("std");
const Aabb = @import("aabb.zig").Aabb;

const assert = std.debug.assert;

pub fn TreeNode(comptime T: type) type {
    return struct {
        aabb: AABB,
        height: i32 = -1,
        child1: ?u32 = null,
        child2: ?u32 = null,
        parent: ?u32 = null,
        move: bool = true,

        const AABB = Aabb(T);
        const Self = @This();

        pub fn isLeaf(self: Self) bool {
            return self.child1 == null;
        }
    };
}

pub fn DynamicTree(comptime T: type) type {
    return struct {
        m_root: ?u32 = null,
        m_nodes: std.ArrayList(Node),
        m_freeList: std.ArrayList(u32),

        pub const Node = TreeNode(T);
        pub const AABB = Node.AABB;
        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator) Self {
            return .{
                .m_nodes = std.ArrayList(Node).init(allocator),
                .m_freeList = std.ArrayList(u32).init(allocator),
            };
        }
        pub fn deinit(self: *Self) void {
            self.m_nodes.deinit();
            self.m_freeList.deinit();
        }
        pub fn query(self: Self, aabb: AABB, callback: anytype) void {
            var stack = std.ArrayList(?u32).init(std.testing.allocator);
            stack.append(self.m_root) catch unreachable;
            while (stack.items.len > 0) {
                const node_id = stack.pop();
                if (node_id == null) {
                    continue;
                }
                const node = self.m_nodes.items[node_id.?];

                if (node.aabb.testOverlap(aabb)) {
                    if (node.isLeaf()) {
                        const proceed = callback(node_id.?);
                        if (proceed == false) return;
                    } else {
                        stack.append(node.child1) catch unreachable;
                        stack.append(node.child2) catch unreachable;
                    }
                }
            }
        }

        pub fn print(self: Self) void {
            std.debug.print("m_nodes: {any}\n", .{self.m_nodes.items});
            std.debug.print("m_freeList: {any}\n", .{self.m_freeList.items});
        }

        pub fn addNode(self: *Self, aabb: AABB) u32 {
            const node_id = self.allocateNode();
            var node = &self.m_nodes.items[node_id];
            node.aabb = aabb;
            node.height = 0;
            self.insertLeaf(node_id);
            return node_id;
        }

        pub fn removeNode(self: *Self, node_id: u32) void {
            self.removeLeaf(node_id);
            self.freeNode(node_id);
        }

        fn allocateNode(self: *Self) u32 {
            const node_id = self.m_freeList.popOrNull();
            if (node_id == null) {
                self.m_nodes.append(Node{
                    .aabb = AABB.zero(),
                }) catch unreachable;
                return @intCast(u32, self.m_nodes.items.len - 1);
            }
            return node_id.?;
        }

        fn freeNode(self: *Self, node_id: u32) void {
            // TODO: b2Assert(0 <= nodeId && nodeId < m_nodeCapacity);
            // b2Assert(0 < m_nodeCount);
            self.m_freeList.append(node_id) catch unreachable;
            self.m_nodes.items[node_id].height = -1;
        }

        fn insertLeaf(self: *Self, leaf: u32) void {
            // TODO: what is this? self.m_insertionCount += 1;
            var m_nodes = self.m_nodes.items;
            if (self.m_root == null) {
                self.m_root = leaf;
                m_nodes[leaf].parent = null;
                return;
            }

            // Find the best sibling for this node
            var leafAABB = m_nodes[leaf].aabb;
            var index = self.m_root.?;
            while (m_nodes[index].isLeaf() == false) {
                const child1 = m_nodes[index].child1.?;
                const child2 = m_nodes[index].child2.?;

                const area = m_nodes[index].aabb.getPerimeter();

                const combined_aabb = AABB.combine(m_nodes[index].aabb, leafAABB);
                const combined_area = combined_aabb.getPerimeter();

                // Cost of creating a new parent for this node and the new leaf
                const cost = 2 * combined_area;

                // Minimum cost of pushing the leaf further down the tree
                const inheritance_cost = 2 * (combined_area - area);

                // Cost of descending into child1
                var cost1: T = undefined;
                if (m_nodes[child1].isLeaf()) {
                    const aabb = AABB.combine(leafAABB, m_nodes[child1].aabb);
                    cost1 = aabb.getPerimeter() + inheritance_cost;
                } else {
                    const aabb = AABB.combine(leafAABB, m_nodes[child1].aabb);
                    const old_area = m_nodes[child1].aabb.getPerimeter();
                    const new_area = aabb.getPerimeter();
                    cost1 = (new_area - old_area) + inheritance_cost;
                }

                // Cost of descending into child2
                var cost2: T = undefined;
                if (m_nodes[child2].isLeaf()) {
                    const aabb = AABB.combine(leafAABB, m_nodes[child2].aabb);
                    cost2 = aabb.getPerimeter() + inheritance_cost;
                } else {
                    const aabb = AABB.combine(leafAABB, m_nodes[child2].aabb);
                    const old_area = m_nodes[child2].aabb.getPerimeter();
                    const new_area = aabb.getPerimeter();
                    cost2 = new_area - old_area + inheritance_cost;
                }

                // Descend according to the minimum cost.
                if (cost < cost1 and cost < cost2) break;

                // Descend
                if (cost1 < cost2) {
                    index = child1;
                } else {
                    index = child2;
                }
            }

            const sibling = index;

            // Create a new parent.
            const old_parent = m_nodes[sibling].parent;
            const new_parent = self.allocateNode();
            m_nodes = self.m_nodes.items;
            m_nodes[new_parent].parent = old_parent;
            m_nodes[new_parent].aabb = AABB.combine(leafAABB, m_nodes[sibling].aabb);
            m_nodes[new_parent].height = m_nodes[sibling].height + 1;

            if (old_parent != null) {
                // The sibling was not the root.
                if (m_nodes[old_parent.?].child1 == sibling) {
                    m_nodes[old_parent.?].child1 = new_parent;
                } else {
                    m_nodes[old_parent.?].child2 = new_parent;
                }

                m_nodes[new_parent].child1 = sibling;
                m_nodes[new_parent].child2 = leaf;
                m_nodes[sibling].parent = new_parent;
                m_nodes[leaf].parent = new_parent;
            } else {
                // The sibling was the root.
                m_nodes[new_parent].child1 = sibling;
                m_nodes[new_parent].child2 = leaf;
                m_nodes[sibling].parent = new_parent;
                m_nodes[leaf].parent = new_parent;
                self.m_root = new_parent;
            }

            // Walk back up the tree fixing heights and AABBs
            var i = m_nodes[leaf].parent;
            while (i != null) : (i = m_nodes[i.?].parent) {
                i = self.balance(i.?);

                var child1 = m_nodes[i.?].child1;
                var child2 = m_nodes[i.?].child2;

                // TODO: b2Assert(child1 != b2_nullNode);
                assert(child1 != null);
                //b2Assert(child2 != b2_nullNode);

                m_nodes[i.?].height = 1 + std.math.max(
                    m_nodes[child1.?].height,
                    m_nodes[child2.?].height,
                );
                m_nodes[i.?].aabb = AABB.combine(m_nodes[child1.?].aabb, m_nodes[child2.?].aabb);
            }
        }
        fn balance(self: *Self, node_id: ?u32) u32 {

            // TODO: assert(iA != b2_nullNode);
            assert(node_id != null);
            const ia = node_id.?;
            var m_nodes = self.m_nodes.items;
            var a = &m_nodes[ia];
            if (a.isLeaf() and a.height < 2) {
                return ia;
            }

            const ib = a.child1.?;
            const ic = a.child2.?;
            // TODO: b2Assert(0 <= iB && iB < m_nodeCapacity);
            //b2Assert(0 <= iC && iC < m_nodeCapacity);

            var b = &m_nodes[ib];
            var c = &m_nodes[ic];
            const balance_height = c.height - b.height;

            // Rotate C up
            if (balance_height > 1) {
                const iF = c.child1.?;
                const ig = c.child2.?;
                var f = &m_nodes[iF];
                var g = &m_nodes[ig];
                // TODO: b2Assert(0 <= iF && iF < m_nodeCapacity);
                //b2Assert(0 <= iG && iG < m_nodeCapacity);

                // Swap A and C
                c.child1 = ia;
                c.parent = a.parent;
                a.parent = ic;

                // A's old parent should point to C
                if (c.parent != null) {
                    const c_parent = c.parent.?;
                    if (m_nodes[c_parent].child1 == ia) {
                        m_nodes[c_parent].child1 = ic;
                    } else {
                        // TODO: b2Assert(m_nodes[C.parent].child2 == iA);
                        assert(m_nodes[c.parent.?].child2.? == ia);
                        m_nodes[c_parent].child2 = ic;
                    }
                } else {
                    self.m_root = ic;
                }

                // Rotate
                if (f.height > g.height) {
                    c.child2 = iF;
                    a.child2 = ig;
                    g.parent = ia;
                    a.aabb = AABB.combine(b.aabb, g.aabb);
                    c.aabb = AABB.combine(a.aabb, f.aabb);

                    a.height = 1 + std.math.max(b.height, g.height);
                    c.height = 1 + std.math.max(a.height, f.height);
                } else {
                    c.child2 = ig;
                    a.child2 = iF;
                    f.parent = ia;
                    a.aabb = AABB.combine(b.aabb, f.aabb);
                    c.aabb = AABB.combine(a.aabb, g.aabb);

                    a.height = 1 + std.math.max(b.height, f.height);
                    c.height = 1 + std.math.max(a.height, g.height);
                }

                return ic;
            }

            // Rotate B up
            if (balance_height < -1) {
                const id = b.child1.?;
                const ie = b.child2.?;
                var d = &m_nodes[id];
                var e = &m_nodes[ie];
                // TODO: b2Assert(0 <= iD && iD < m_nodeCapacity);
                //b2Assert(0 <= iE && iE < m_nodeCapacity);

                // Swap A and B
                b.child1 = ia;
                b.parent = a.parent;
                a.parent = ib;

                // A's old parent should point to B
                if (b.parent != null) {
                    const b_parent = b.parent.?;
                    if (m_nodes[b_parent].child1 == ia) {
                        m_nodes[b_parent].child1 = ib;
                    } else {
                        // TODO: b2Assert(m_nodes[B.parent].child2 == iA);
                        assert(m_nodes[b.parent.?].child2.? == ia);
                        m_nodes[b_parent].child2 = ib;
                    }
                } else {
                    self.m_root = ib;
                }

                // Rotate
                if (d.height > e.height) {
                    b.child2 = id;
                    a.child1 = ie;
                    e.parent = ia;
                    a.aabb = AABB.combine(c.aabb, e.aabb);
                    b.aabb = AABB.combine(a.aabb, d.aabb);

                    a.height = 1 + std.math.max(c.height, e.height);
                    b.height = 1 + std.math.max(a.height, d.height);
                } else {
                    b.child2 = ie;
                    a.child1 = id;
                    d.parent = ia;
                    a.aabb = AABB.combine(c.aabb, d.aabb);
                    b.aabb = AABB.combine(a.aabb, e.aabb);

                    a.height = 1 + std.math.max(c.height, d.height);
                    b.height = 1 + std.math.max(a.height, e.height);
                }

                return ib;
            }

            return ia;
        }
        fn removeLeaf(self: *Self, leaf: u32) void {
            // TODO: assert self.m_root != null
            assert(self.m_root != null);
            if (leaf == self.m_root.?) {
                self.m_root = null;
                return;
            }
            var m_nodes = self.m_nodes.items;
            const parent = m_nodes[leaf].parent.?;
            var grand_parent = m_nodes[parent].parent;
            var sibling: u32 = undefined;
            if (m_nodes[parent].child1.? == leaf) {
                sibling = m_nodes[parent].child2.?;
            } else {
                sibling = m_nodes[parent].child1.?;
            }

            if (grand_parent != null) {
                // Destroy parent and connect sibling to grandParent.
                if (m_nodes[grand_parent.?].child1 == parent) {
                    m_nodes[grand_parent.?].child1 = sibling;
                } else {
                    m_nodes[grand_parent.?].child2 = sibling;
                }
                m_nodes[sibling].parent = grand_parent.?;
                self.freeNode(parent);

                // Adjust ancestor bounds.
                var index: ?u32 = grand_parent;
                while (index != null) : (index = m_nodes[index.?].parent) {
                    index = self.balance(index.?);

                    const child1 = m_nodes[index.?].child1.?;
                    const child2 = m_nodes[index.?].child2.?;

                    m_nodes[index.?].aabb = AABB.combine(
                        m_nodes[child1].aabb,
                        m_nodes[child2].aabb,
                    );
                    m_nodes[index.?].height = 1 + std.math.max(
                        m_nodes[child1].height,
                        m_nodes[child2].height,
                    );
                }
            } else {
                self.m_root = sibling;
                m_nodes[sibling].parent = null;
                self.freeNode(parent);
            }

            //Validate();
        }
    };
}

fn queryCallback(node_id: u32) bool {
    std.debug.print("Overlap with: {}\n", .{node_id});
    return true;
}

test "Dynamic Tree add/remove Node" {
    var dt = DynamicTree.init(std.testing.allocator);
    defer dt.deinit();
    const AABB = DynamicTree.AABB;
    const Vec2 = AABB.Vec2;
    const aabb = AABB.new(
        Vec2.new(4, 4),
        Vec2.new(1, 1),
    );
    const aabb1 = AABB.new(
        Vec2.new(3, 3),
        Vec2.new(2, 2),
    );

    std.debug.print("==== query 1 ====\n", .{});
    dt.query(aabb1, queryCallback);

    var id = dt.addNode(aabb);

    std.debug.print("==== query 2 ====\n", .{});
    dt.query(aabb1, queryCallback);

    id = dt.addNode(aabb);
    dt.removeNode(id);

    std.debug.print("==== query 3 ====\n", .{});
    dt.query(aabb1, queryCallback);

    id = dt.addNode(aabb);

    std.debug.print("==== query 4 ====\n", .{});
    dt.query(aabb1, queryCallback);

    dt.removeNode(id);

    std.debug.print("==== query 5 ====\n", .{});
    dt.query(aabb1, queryCallback);
}
