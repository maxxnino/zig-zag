const std = @import("std");
const testing = std.testing;
const Vector2 = @import("zalgebra").Vector2;
const za = @import("zalgebra");
pub const RectInt = Rect(i32);
pub const RectFloat = Rect(f32);

pub fn Rect(comptime T: type) type {
    return struct {
        pub const Vec2 = Vector2(T);
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
                .lower_bound = m_pos.sub(h_size),
                .upper_bound = m_pos.add(h_size),
            };
        }

        pub fn newRectInt(m_pos: Vec2, h_size: Vec2, screen: Vec2, screen_size: Vec2) RectInt {
            return .{
                .lower_bound = .{
                    .x = @floatToInt(i32, m_pos.x - screen.x + screen_size.x - h_size.x),
                    .y = @floatToInt(i32, screen.y + screen_size.y - m_pos.y - h_size.y),
                },
                .upper_bound = .{
                    .x = @floatToInt(i32, h_size.x * 2),
                    .y = @floatToInt(i32, h_size.y * 2),
                },
            };
        }

        pub fn extent(self: Self, size: Vec2) Self {
            return .{
                .lower_bound = self.lower_bound.sub(size),
                .upper_bound = self.upper_bound.add(size),
            };
        }

        pub fn testOverlap(a: Self, b: Self) bool {
            const d1 = Vec2.sub(b.lower_bound, a.upper_bound);
            const d2 = Vec2.sub(a.lower_bound, b.upper_bound);
            if (d1.x > 0 or d1.y > 0) return false;
            if (d2.x > 0 or d2.y > 0) return false;
            return true;
        }

        /// Contruct new aabb with 2 given aabb
        pub fn combine(a: Self, b: Self) Self {
            return Self.new(
                Vec2.min(a.lower_bound, b.lower_bound),
                Vec2.max(a.upper_bound, b.upper_bound),
            );
        }

        pub fn contains(a: Self, b: Self) bool {
            var result = true;
            result = result and a.lower_bound.x <= b.lower_bound.x;
            result = result and a.lower_bound.y <= b.lower_bound.y;
            result = result and b.upper_bound.x <= a.upper_bound.x;
            result = result and b.upper_bound.y <= a.upper_bound.y;
            return result;
        }

        pub fn getPerimeter(self: Self) T {
            const wx = self.upper_bound.x - self.lower_bound.x;
            const wy = self.upper_bound.y - self.lower_bound.y;
            return 2 * (wx + wy);
        }

        pub fn bottomLeft(self: Self) Vec2 {
            return self.lower_bound;
        }

        pub fn topRight(self: Self) Vec2 {
            return self.upper_bound;
        }

        pub fn bottomRight(self: Self) Vec2 {
            return Vec2.new(self.upper_bound.x, self.lower_bound.y);
        }

        pub fn topLeft(self: Self) Vec2 {
            return Vec2.new(self.lower_bound.x, self.upper_bound.y);
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
    const a2 = RectInt.new(v3, v4);

    try testing.expect(a1.testOverlap(a2));
    try testing.expect(a1.getPerimeter() == 8);

    const a3 = a1.combine(a2);
    try testing.expect(a3.lower_bound.eql(v1) and a3.upper_bound.eql(v4));
}
