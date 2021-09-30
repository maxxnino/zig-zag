const std = @import("std");
const expect = std.testing.expect;
pub fn Generator(
    comptime Ctx: type,
    comptime T: type,
    comptime func: fn (Ctx, *?T) void,
) type {
    return struct {
        const State = enum {
            start,
            process,
        };
        const Self = @This();
        frame: @Frame(func),
        state: State,
        ctx: Ctx,
        return_type: ?T,

        pub fn next(self: *Self) ?T {
            switch (self.state) {
                .start => {
                    self.frame = @call(
                        .{ .modifier = .async_kw },
                        func,
                        .{ self.ctx, &self.return_type },
                    );
                    self.state = .process;
                    return self.next();
                },
                .process => {
                    if (self.return_type) |value| {
                        resume self.frame;
                        return value;
                    }
                    return null;
                },
            }
        }
        pub fn init(ctx: Ctx) Self {
            return .{
                .frame = undefined,
                .state = .start,
                .ctx = ctx,
                .return_type = null,
            };
        }
    };
}

fn do(ctx: void, return_type: *?u32) void {
    _ = ctx;
    return_type.* = 0;
    suspend {}
    return_type.* = 10;
    suspend {}
    return_type.* = null;
}

test "basic" {
    var it = Generator(void, u32, do).init({});
    try expect(it.next().? == 0);
    try expect(it.next().? == 10);
    try expect(it.next() == null);
    try expect(it.next() == null);
}
