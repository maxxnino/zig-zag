const std = @import("std");
const Vec2 = @import("Vec2.zig").Vec2;
const AABB = struct {
    upper_bound: Vec2,
    lower_bound: Vec2,
    pub fn zero() AABB {
        return AABB{
            .upper_bound = Vec2.zero(),
            .lower_bound = Vec2.zero(),
        };
    }
    pub fn combine(self: *AABB, aabb1: AABB, aabb2: AABB) void {
        self.lower_bound = Vec2.min(aabb1.lower_bound, aabb2.lower_bound);
        self.upper_bound = Vec2.max(aabb1.upper_bound, aabb2.upper_bound);
    }

    pub fn getPerimeter(self: AABB) f32 {
        const wx = self.upper_bound.x - self.lower_bound.x;
        const wy = self.upper_bound.y - self.lower_bound.y;
        return 2 * (wx + wy);
    }
};
const Node = struct {
    aabb: AABB,
    height: i32 = -1,
    child1: ?u32 = null,
    child2: ?u32 = null,
    parent: ?u32 = null,
    move: bool = true,
    pub fn isLeaf(self: Node) bool {
        return self.child1 == null;
    }
};
const DynamicTree = struct {
    m_root: ?u32 = null,
    m_nodes: std.ArrayList(Node),
    // m_nodeCount: i32,
    // m_nodeCapacity: i32,
    m_freeList: std.ArrayList(u32),
    // m_insertionCount: i32,

    pub fn addNode(self: *DynamicTree, aabb: AABB) u32 {
        const node_id = self.allocateNode();
        var node = &self.m_nodes.items[node_id];
        node.aabb = aabb;
        node.height = 0;
        self.insertLeaf(node_id);
        return node_id;
    }

    pub fn removeNode(self: *DynamicTree, node_id: u32) void {
        self.removeLeaf(node_id);
        self.freeNode(node_id);
    }

    fn allocateNode(self: *DynamicTree) u32 {
        const node_id = self.m_freeList.popOrNull();
        if (node_id == null) {
            self.m_nodes.append(Node{
                .aabb = AABB.zero(),
            }) catch unreachable;
            std.debug.print("allocateNode: {}\n", .{self.m_nodes.items.len - 1});
            return @intCast(u32, self.m_nodes.items.len - 1);
        }
        std.debug.print("reuse allocateNode: {}\n", .{node_id.?});
        return node_id.?;
    }

    fn freeNode(self: *DynamicTree, node_id: u32) void {
        // TODO: b2Assert(0 <= nodeId && nodeId < m_nodeCapacity);
        // b2Assert(0 < m_nodeCount);
        self.m_freeList.append(node_id) catch unreachable;
        self.m_nodes.items[node_id].height = -1;
    }

    fn insertLeaf(self: *DynamicTree, leaf: u32) void {
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

            var combinedAABB = AABB.zero();
            combinedAABB.combine(m_nodes[index].aabb, leafAABB);
            const combinedArea = combinedAABB.getPerimeter();

            // Cost of creating a new parent for this node and the new leaf
            const cost = 2.0 * combinedArea;

            // Minimum cost of pushing the leaf further down the tree
            const inheritanceCost = 2.0 * (combinedArea - area);

            // Cost of descending into child1
            var cost1: f32 = undefined;
            if (m_nodes[child1].isLeaf()) {
                var aabb = AABB.zero();
                aabb.combine(leafAABB, m_nodes[child1].aabb);
                cost1 = aabb.getPerimeter() + inheritanceCost;
            } else {
                var aabb = AABB.zero();
                aabb.combine(leafAABB, m_nodes[child1].aabb);
                const oldArea = m_nodes[child1].aabb.getPerimeter();
                const newArea = aabb.getPerimeter();
                cost1 = (newArea - oldArea) + inheritanceCost;
            }

            // Cost of descending into child2
            var cost2: f32 = undefined;
            if (m_nodes[child2].isLeaf()) {
                var aabb = AABB.zero();
                aabb.combine(leafAABB, m_nodes[child2].aabb);
                cost2 = aabb.getPerimeter() + inheritanceCost;
            } else {
                var aabb = AABB.zero();
                aabb.combine(leafAABB, m_nodes[child2].aabb);
                const oldArea = m_nodes[child2].aabb.getPerimeter();
                const newArea = aabb.getPerimeter();
                cost2 = newArea - oldArea + inheritanceCost;
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
        const oldParent = m_nodes[sibling].parent;
        const newParent = self.allocateNode();
        m_nodes = self.m_nodes.items;
        m_nodes[newParent].parent = oldParent;
        m_nodes[newParent].aabb.combine(leafAABB, m_nodes[sibling].aabb);
        m_nodes[newParent].height = m_nodes[sibling].height + 1;

        if (oldParent != null) {
            // The sibling was not the root.
            if (m_nodes[oldParent.?].child1 == sibling) {
                m_nodes[oldParent.?].child1 = newParent;
            } else {
                m_nodes[oldParent.?].child2 = newParent;
            }

            m_nodes[newParent].child1 = sibling;
            m_nodes[newParent].child2 = leaf;
            m_nodes[sibling].parent = newParent;
            m_nodes[leaf].parent = newParent;
        } else {
            // The sibling was the root.
            m_nodes[newParent].child1 = sibling;
            m_nodes[newParent].child2 = leaf;
            m_nodes[sibling].parent = newParent;
            m_nodes[leaf].parent = newParent;
            self.m_root = newParent;
        }

        // Walk back up the tree fixing heights and AABBs
        var i = m_nodes[leaf].parent;
        while (i != null) : (i = m_nodes[i.?].parent) {
            i = self.Balance(i.?);

            var child1 = m_nodes[i.?].child1;
            var child2 = m_nodes[i.?].child2;

            // TODO: b2Assert(child1 != b2_nullNode);
            //b2Assert(child2 != b2_nullNode);

            m_nodes[i.?].height = 1 + std.math.max(
                m_nodes[child1.?].height,
                m_nodes[child2.?].height,
            );
            m_nodes[i.?].aabb.combine(m_nodes[child1.?].aabb, m_nodes[child2.?].aabb);
        }
    }
    fn Balance(self: *DynamicTree, iA: u32) u32 {

        // TODO: b2Assert(iA != b2_nullNode);
        var m_nodes = self.m_nodes.items;
        var A = &m_nodes[iA];
        if (A.isLeaf() and A.height < 2) {
            return iA;
        }

        const iB = A.child1.?;
        const iC = A.child2.?;
        // TODO: b2Assert(0 <= iB && iB < m_nodeCapacity);
        //b2Assert(0 <= iC && iC < m_nodeCapacity);

        var B = &m_nodes[iB];
        var C = &m_nodes[iC];
        const balance = C.height - B.height;

        // Rotate C up
        if (balance > 1) {
            const iF = C.child1.?;
            const iG = C.child2.?;
            var F = &m_nodes[iF];
            var G = &m_nodes[iG];
            // TODO: b2Assert(0 <= iF && iF < m_nodeCapacity);
            //b2Assert(0 <= iG && iG < m_nodeCapacity);

            // Swap A and C
            C.child1 = iA;
            C.parent = A.parent;
            A.parent = iC;

            // A's old parent should point to C
            if (C.parent != null) {
                const c_parent = C.parent.?;
                if (m_nodes[c_parent].child1 == iA) {
                    m_nodes[c_parent].child1 = iC;
                } else {
                    // TODO: b2Assert(m_nodes[C.parent].child2 == iA);
                    m_nodes[c_parent].child2 = iC;
                }
            } else {
                self.m_root = iC;
            }

            // Rotate
            if (F.height > G.height) {
                C.child2 = iF;
                A.child2 = iG;
                G.parent = iA;
                A.aabb.combine(B.aabb, G.aabb);
                C.aabb.combine(A.aabb, F.aabb);

                A.height = 1 + std.math.max(B.height, G.height);
                C.height = 1 + std.math.max(A.height, F.height);
            } else {
                C.child2 = iG;
                A.child2 = iF;
                F.parent = iA;
                A.aabb.combine(B.aabb, F.aabb);
                C.aabb.combine(A.aabb, G.aabb);

                A.height = 1 + std.math.max(B.height, F.height);
                C.height = 1 + std.math.max(A.height, G.height);
            }

            return iC;
        }

        // Rotate B up
        if (balance < -1) {
            const iD = B.child1.?;
            const iE = B.child2.?;
            var D = &m_nodes[iD];
            var E = &m_nodes[iE];
            // TODO: b2Assert(0 <= iD && iD < m_nodeCapacity);
            //b2Assert(0 <= iE && iE < m_nodeCapacity);

            // Swap A and B
            B.child1 = iA;
            B.parent = A.parent;
            A.parent = iB;

            // A's old parent should point to B
            if (B.parent != null) {
                const b_parent = B.parent.?;
                if (m_nodes[b_parent].child1 == iA) {
                    m_nodes[b_parent].child1 = iB;
                } else {
                    // TODO: b2Assert(m_nodes[B.parent].child2 == iA);
                    m_nodes[b_parent].child2 = iB;
                }
            } else {
                self.m_root = iB;
            }

            // Rotate
            if (D.height > E.height) {
                B.child2 = iD;
                A.child1 = iE;
                E.parent = iA;
                A.aabb.combine(C.aabb, E.aabb);
                B.aabb.combine(A.aabb, D.aabb);

                A.height = 1 + std.math.max(C.height, E.height);
                B.height = 1 + std.math.max(A.height, D.height);
            } else {
                B.child2 = iE;
                A.child1 = iD;
                D.parent = iA;
                A.aabb.combine(C.aabb, D.aabb);
                B.aabb.combine(A.aabb, E.aabb);

                A.height = 1 + std.math.max(C.height, D.height);
                B.height = 1 + std.math.max(A.height, E.height);
            }

            return iB;
        }

        return iA;
    }
    fn removeLeaf(self: *DynamicTree, leaf: u32) void {
        // TODO: assert self.m_root != null
        if (leaf == self.m_root.?) {
            self.m_root = null;
            return;
        }
        var m_nodes = self.m_nodes.items;
        const parent = m_nodes[leaf].parent.?;
        var grandParent = m_nodes[parent].parent;
        var sibling: u32 = undefined;
        if (m_nodes[parent].child1.? == leaf) {
            sibling = m_nodes[parent].child2.?;
        } else {
            sibling = m_nodes[parent].child1.?;
        }

        if (grandParent != null) {
            // Destroy parent and connect sibling to grandParent.
            if (m_nodes[grandParent.?].child1 == parent) {
                m_nodes[grandParent.?].child1 = sibling;
            } else {
                m_nodes[grandParent.?].child2 = sibling;
            }
            m_nodes[sibling].parent = grandParent.?;
            // TODO:
            self.freeNode(parent);

            // Adjust ancestor bounds.
            var index: ?u32 = grandParent;
            while (index != null) : (index = m_nodes[index.?].parent) {
                index = self.Balance(index.?);

                const child1 = m_nodes[index.?].child1.?;
                const child2 = m_nodes[index.?].child2.?;

                m_nodes[index.?].aabb.combine(m_nodes[child1].aabb, m_nodes[child2].aabb);
                m_nodes[index.?].height = 1 + std.math.max(
                    m_nodes[child1].height,
                    m_nodes[child2].height,
                );
            }
        } else {
            self.m_root = sibling;
            m_nodes[sibling].parent = null;
            // TODO:
            self.freeNode(parent);
        }

        //Validate();
    }
};
test "Dynamic Tree add/remove Node" {
    var dt = DynamicTree{
        .m_nodes = std.ArrayList(Node).init(std.testing.allocator),
        .m_freeList = std.ArrayList(u32).init(std.testing.allocator),
    };
    var id = dt.addNode(AABB{
        .upper_bound = Vec2.new(1, 2),
        .lower_bound = Vec2.new(3, 4),
    });
    id = dt.addNode(AABB{
        .upper_bound = Vec2.new(1, 2),
        .lower_bound = Vec2.new(3, 4),
    });
    dt.removeNode(id);

    id = dt.addNode(AABB{
        .upper_bound = Vec2.new(1, 2),
        .lower_bound = Vec2.new(3, 4),
    });
    std.log.info("{}\n", .{id});
}
pub fn main() anyerror!void {
    var dt = DynamicTree{
        .m_nodes = std.ArrayList(Node).init(std.testing.allocator),
        .m_freeList = std.ArrayList(u32).init(std.testing.allocator),
    };
    var id = dt.addNode(AABB{
        .upper_bound = Vec2.new(1, 2),
        .lower_bound = Vec2.new(3, 4),
    });
    id = dt.addNode(AABB{
        .upper_bound = Vec2.new(1, 2),
        .lower_bound = Vec2.new(3, 4),
    });
    dt.removeNode(id);

    id = dt.addNode(AABB{
        .upper_bound = Vec2.new(1, 2),
        .lower_bound = Vec2.new(3, 4),
    });
    dt.removeNode(id);
    id = dt.addNode(AABB{
        .upper_bound = Vec2.new(1, 2),
        .lower_bound = Vec2.new(3, 4),
    });
    id = dt.addNode(AABB{
        .upper_bound = Vec2.new(1, 2),
        .lower_bound = Vec2.new(3, 4),
    });
    std.log.info("{}\n", .{id});
}
