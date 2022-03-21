const std = @import("std");
const testing = std.testing;
const za = @import("zalgebra");
pub const RectInt = Rect(i32);
pub const RectFloat = Rect(f32);

pub fn Rect(comptime T: type) type {
    return struct {
        pub const Vec2 = za.GenericVector(2, T);
        const Self = @This();

        lower_bound: Vec2,
        upper_bound: Vec2,

        /// Contruct Rectangle form given 2 Vector2
        pub fn new(lower_bound: Vec2, upper_bound: Vec2) Self {
            return .{
                .lower_bound = lower_bound,
                .upper_bound = upper_bound,
            };
        }

        pub fn newFromCenter(m_pos: Vec2, h_size: Vec2) Self {
            return .{
                .lower_bound = .{ .data = m_pos.data - h_size.data },
                .upper_bound = .{ .data = m_pos.data + h_size.data },
            };
        }

        pub fn toScreenSpace(m_pos: Vec2, h_size: Vec2, screen: Vec2, screen_size: Vec2, pixel: T) RectInt {
            const x = @Vector(4, T){ m_pos.x(), -screen.x(), screen_size.x(), -h_size.x() };
            const y = @Vector(4, T){ -m_pos.y(), screen.y(), screen_size.y(), -h_size.y() };
            return .{
                .lower_bound = Vec2.new(@reduce(.Add, x), @reduce(.Add, y)).scale(pixel).cast(i32),
                .upper_bound = h_size.scale(pixel * 2).cast(i32),
            };
        }

        pub fn posToScreenSpace(m_pos: Vec2, screen: Vec2, screen_size: Vec2, pixel: T) za.GenericVector(i32) {
            const x = @Vector(3, T){ m_pos.x(), -screen.x(), screen_size.x() };
            const y = @Vector(3, T){ -m_pos.y(), screen.y(), screen_size.y() };
            return za.GenericVector(i32).new(@reduce(.Add, x), @reduce(.Add, y).scale(pixel).cast(i32));
        }

        pub fn extent(self: Self, size: Vec2) Self {
            return .{
                .lower_bound = self.lower_bound.sub(size),
                .upper_bound = self.upper_bound.add(size),
            };
        }

        pub fn testOverlap(a: Self, b: Self) bool {
            const d1 = b.lower_bound.sub(a.upper_bound);
            if (@reduce(.Or, d1.data > Vec2.zero().data)) return false;

            const d2 = a.lower_bound.sub(b.upper_bound);
            if (@reduce(.Or, d2.data > Vec2.zero().data)) return false;
            return true;
        }

        /// Contruct new aabb with 2 given aabb
        pub fn combine(a: Self, b: Self) Self {
            return Self.new(
                Vec2.min(a.lower_bound, b.lower_bound),
                Vec2.max(a.upper_bound, b.upper_bound),
            );
        }

        // pub fn contains1(a: Self, b: Self) bool {
        //     return @reduce(.And, a.lower_bound.data <= b.lower_bound.data) and
        //         @reduce(.And, b.upper_bound.data <= a.upper_bound.data);
        // }

        pub fn contains(a: Self, b: Self) bool {
            const lhs = @Vector(4, T){ a.lower_bound.x(), a.lower_bound.y(), b.upper_bound.x(), b.upper_bound.y() };
            const rhs = @Vector(4, T){ b.lower_bound.x(), b.lower_bound.y(), a.upper_bound.x(), a.upper_bound.y() };
            return @reduce(.And, lhs <= rhs);
        }

        pub fn getPerimeter(self: Self) T {
            return 2 * @reduce(.Add, self.upper_bound.sub(self.lower_bound).data);
        }

        pub fn bottomLeft(self: Self) Vec2 {
            return self.lower_bound;
        }

        pub fn topRight(self: Self) Vec2 {
            return self.upper_bound;
        }

        pub fn bottomRight(self: Self) Vec2 {
            return Vec2.new(self.upper_bound.x(), self.lower_bound.y());
        }

        pub fn topLeft(self: Self) Vec2 {
            return Vec2.new(self.lower_bound.x(), self.upper_bound.y());
        }

        pub fn zero() Self {
            return Self.new(Vec2.zero(), Vec2.zero());
        }
    };
}

test "basic" {
    const Vec2 = RectInt.Vec2;

    const v1 = Vec2.new(1, 1);
    const v2 = Vec2.new(3, 3);
    const v3 = Vec2.new(2, 2);
    const v4 = Vec2.new(4, 4);

    const a1 = RectInt.new(v1, v2);
    const a2 = RectInt.newFromCenter(v3, v4);
    const a3 = a1.extent(v1);
    const a4 = a1.combine(a2);

    try testing.expect(a1.testOverlap(a3));
    try testing.expect(a3.testOverlap(a1));
    try testing.expect(a3.testOverlap(a4));
    try testing.expect(a4.testOverlap(a2));
    try testing.expect(a2.testOverlap(a4));

    const a5 = RectInt.newFromCenter(v1, v2);

    try testing.expect(a5.contains(a1));
    try testing.expect(a1.getPerimeter() == 8);
}
