const std = @import("std");

pub const Zroutine = struct {
    other: *Zroutine,

    rip: ?*const fn (*Zroutine, ?*anyopaque) callconv(.c) ?*anyopaque = null,
    stack: []u8,
    rsp: *anyopaque,
    rbp: *anyopaque,
    allocator: std.mem.Allocator,
    yieldTo: ?*Zroutine = null,

    pub fn new(function: *const fn (*Zroutine, ?*anyopaque) callconv(.c) ?*anyopaque, allocator: std.mem.Allocator) !*Zroutine {
        const z = try allocator.create(Zroutine);
        z.allocator = allocator;
        z.stack = try allocator.alloc(u8, 4096 * 100);
        z.rip = function;
        z.rsp = z.stack.ptr + 4096 * 100;
        z.rbp = z.rsp;

        return z;
    }

    pub fn newSelf(allocator: std.mem.Allocator) !*Zroutine {
        const z = try allocator.create(Zroutine);
        z.allocator = allocator;

        return z;
    }

    pub fn contextSwitch(self: *Zroutine, target: *Zroutine, arg: ?*anyopaque) ?*anyopaque {
        return asm volatile (
            \\  # Save information for latter context restore.
            \\  leaq RET(%%rip), %%r9
            \\  movq %%r9, (%%rax)
            \\  movq %%rsp, (%%rbx)
            \\  movq %%rbp, (%%r12)
            \\
            \\  # Switch contexts.
            \\  mov %%rcx, %%rsp
            \\  mov %%r8, %%rbp
            \\  callq *%%rdx
            \\
            \\  # If the switched-to function returns, restore the context,
            \\  # set it's rip to null and skip return emulation.
            \\  movq (%%rbx), %%rsp
            \\  movq (%%r12), %%rbp
            \\  movq $0, (%%r13)
            \\  jmp RET_SKIP_RIP_POP
            \\
            \\RET:
            \\  # Return emulation: pop the rip because we made a call and
            \\  # it "returned" without an actual ret instruction on our
            \\  # stack.
            \\  add $8, %%rsp
            \\  # Copy the argument to the rax because it was passed to us
            \\  # via the rsi.
            \\  mov %%rsi, %%rax
            \\RET_SKIP_RIP_POP:
            : [ret] "={rax}" (-> ?*anyopaque),
              // Pointers to save the self information.
            : [selfRipPtr] "{rax}" (&self.rip),
              [selfRspPtr] "{rbx}" (&self.rsp),
              [selfRbpPtr] "{r12}" (&self.rbp),
              // If the target returns, we need to set it's rip to null.
              [targetRipPtr] "{r13}" (&target.rip),
              // Arguments to the call.
              [target] "{rdi}" (target),
              [arg] "{rsi}" (arg),
              // Information to make the context switch.
              [targetRip] "{rdx}" (target.rip),
              [targetRsp] "{rcx}" (target.rsp),
              [targetRbp] "{r8}" (target.rbp),
              // All registers except by rsp and rbp, as those are properly
              // restored.
            : .{
              .rax = true,
              .rbx = true,
              .rcx = true,
              .rdx = true,
              .rdi = true,
              .rsi = true,
              .r8 = true,
              .r9 = true,
              .r10 = true,
              .r11 = true,
              .r12 = true,
              .r13 = true,
              .r14 = true,
              .r15 = true,
            });
    }

    pub fn next(self: *Zroutine, target: *Zroutine, arg: ?*anyopaque) !?*anyopaque {
        target.yieldTo = self;
        return contextSwitch(self, target, arg);
    }

    pub fn yield(self: *Zroutine, arg: ?*anyopaque) !void {
        if (self.yieldTo) |target| {
            _ = contextSwitch(self, target, arg);
        } else {
            return error.NoYieldTarget;
        }
    }
};

pub fn testf(self: *Zroutine, arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    std.debug.print("got {} from main!\n", .{arg orelse unreachable});
    self.yield(@ptrFromInt(0xb15b00b5)) catch unreachable;
    std.debug.print("returned from yield!\n", .{});
    return @ptrFromInt(0xdeadbeef);
}

pub fn main() !void {
    var dbga = std.heap.DebugAllocator(.{}){};
    const allocator = dbga.allocator();
    const z = try Zroutine.new(testf, allocator);
    const self = try Zroutine.newSelf(allocator);

    const res = self.next(z, @ptrFromInt(0xcafebabe)) catch unreachable;
    std.debug.print("got {} from zroutine!\n", .{res orelse unreachable});
    const res2 = self.next(z, @ptrFromInt(0x1badb002)) catch unreachable;
    std.debug.print("got {} from zroutine!\n", .{res2 orelse unreachable});
}
