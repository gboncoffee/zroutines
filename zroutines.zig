const std = @import("std");

pub const Zroutine = struct {
    other: *Zroutine,

    rip: *const fn (*Zroutine, ?*anyopaque) callconv(.c) ?*anyopaque,
    stack: []u8,
    rsp: *anyopaque,
    allocator: std.mem.Allocator,

    pub fn new(function: *const fn (*Zroutine, ?*anyopaque) callconv(.c) ?*anyopaque, allocator: std.mem.Allocator) !*Zroutine {
        const z = try allocator.create(Zroutine);
        z.allocator = allocator;
        z.stack = try allocator.alloc(u8, 4096 * 100);
        z.rip = function;
        z.rsp = z.stack.ptr + 4096 * 100;

        return z;
    }

    pub fn run(self: *Zroutine, arg: ?*anyopaque) ?*anyopaque {
        var origRsp: [*]u8 = undefined;
        return asm volatile (
            \\  mov %rsp, (%rbx)
            \\  mov %rcx, %rsp
            \\  callq *%rdx
            \\  mov (%rbx), %rsp
            : [ret] "={rax}" (-> ?*anyopaque),
            : [self] "{rdi}" (self),
              [arg] "{rsi}" (arg),
              [rip] "{rdx}" (self.rip),
              [rsp] "{rcx}" (self.rsp),
              [origRspPtr] "{rbx}" (&origRsp),
            : "rax", "rdi", "rsi", "rdx", "rcx", "r8", "r9", "r10", "r11"
        );
    }
};

pub fn testf(_: ?*Zroutine, arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    std.debug.print("got {} from main!\n", .{arg orelse unreachable});
    var res: u8 = 2;
    return @ptrCast(&res);
}

pub fn main() !void {
    var dbga = std.heap.DebugAllocator(.{}){};
    const allocator = dbga.allocator();
    const z = try Zroutine.new(testf, allocator);

    var arg: u8 = 5;
    const res = z.run(&arg);
    std.debug.print("got {} from zroutine!\n", .{res orelse unreachable});
}
