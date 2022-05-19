const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");
var globalAllocator: std.mem.Allocator = undefined;
var exception: std.ArrayList([]const u8) = undefined;
const scoped = std.log.scoped(.WasmBottomProgram);
const RestartState = enum(u32) {
    bottomify_failed = 1,
    regress_failed = 2,
    generic_error = 3,
    panic = 4,
};
var current_state: RestartState = .generic_error;

export fn _start() void {
    var zee = ZeeAlloc(Config{}).init(std.heap.page_allocator);
    globalAllocator = zee.allocator();
    exception = std.ArrayList([]const u8).init(globalAllocator);
}

export fn decode() void {
    current_state = .regress_failed;
    var len = getTextLen();
    if(len > std.math.maxInt(usize)) {
        var err = error.input_too_long;
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@enumToInt(current_state));
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));
        return;
    }
    var text = getText()[0..len];
    var decoded = decoder.BottomDecoder.decodeAlloc(text, globalAllocator) catch |err| {
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@enumToInt(current_state));
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));
        return;
    };
    defer globalAllocator.free(decoded);
    setResult(decoded.ptr, decoded.len);
    hideException();
}
export fn encode() void {
    current_state = .bottomify_failed;
    var len = getTextLen();
    if(len > std.math.maxInt(usize)) {
        var err = error.input_too_long;

        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@enumToInt(current_state));
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));
        return;
    }
    var text = getText()[0..len];
    var encoded = encoder.BottomEncoder.encodeAlloc(text, globalAllocator) catch |err| {
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@enumToInt(current_state));
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));

        globalAllocator.free(message);
        return;
    };
    defer globalAllocator.free(encoded);
    setResult(encoded.ptr, @truncate(u32, encoded.len));
    hideException();
}

extern fn setResult(ptr: [*]const u8, len: u32) void;
extern fn appendException(ptr: [*]const u8, len: u32) void;
extern fn hideException() void;
extern fn getText() [*]const u8;
extern fn getTextLen() u32;
extern fn restart(status: u32) void;
pub extern fn logus(ptr: [*]const u8, len: u32) void;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    current_state = .generic_error;
    var message = std.fmt.allocPrint(globalAllocator, format, args) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@enumToInt(current_state));

        return;
    };
    var to_print = std.fmt.allocPrint(globalAllocator, "{s}-{s}: {s}", .{ @tagName(scope), message_level.asText(), message }) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@enumToInt(current_state));

        return;
    };
    logus(to_print.ptr, @truncate(u32, to_print.len));
    globalAllocator.free(message);
    globalAllocator.free(to_print);
}

pub fn panic(msg: []const u8, stackTrace: ?*std.builtin.StackTrace) noreturn {
    current_state = .panic;
    restart(@enumToInt(current_state));
    var stack_trace_print: ?[]u8 = null;
    if (stackTrace != null) {
        stack_trace_print = std.fmt.allocPrint(globalAllocator, "{s}", .{stackTrace}) catch |err| {
            logus("failed on error:", "failed on error:".len);
            logus(@errorName(err).ptr, @errorName(err).len);
            restart(@enumToInt(current_state));

            trap();
        };
    }

    var message = std.fmt.allocPrint(globalAllocator, "{s}", .{msg}) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@enumToInt(current_state));

        trap();
    };
    var to_print = std.fmt.allocPrint(globalAllocator, "{s}", .{message}) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@enumToInt(current_state));
        trap();
    };
    logus(to_print.ptr, @truncate(u32, to_print.len));
    globalAllocator.free(message);
    globalAllocator.free(to_print);
    if (stack_trace_print != null) {
        globalAllocator.free(stack_trace_print.?);
    }
    trap();
}

inline fn trap() noreturn {
    while (true) {
        @breakpoint();
    }
}


const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const meta_size = 2 * @sizeOf(usize);
const min_payload_size = meta_size;
const min_frame_size = meta_size + min_payload_size;

const jumbo_index = 0;
const page_index = 1;

pub const ZeeAllocDefaults = ZeeAlloc(Config{});

pub const Config = struct {
    /// ZeeAlloc will request a multiple of `page_size` from the backing allocator.
    /// **Must** be a power of two.
    page_size: usize = std.math.max(std.mem.page_size, 65536), // 64K ought to be enough for everybody
    validation: Validation = .External,

    jumbo_match_strategy: JumboMatchStrategy = .Closest,
    buddy_strategy: BuddyStrategy = .Fast,
    shrink_strategy: ShrinkStrategy = .Defer,

    pub const JumboMatchStrategy = enum {
        /// Use the frame that wastes the least space
        /// Scans the entire jumbo freelist, which is slower but keeps memory pretty tidy
        Closest,

        /// Use only exact matches
        /// -75 bytes vs `.Closest`
        /// Similar performance to Closest if allocation sizes are consistent throughout lifetime
        Exact,

        /// Use the first frame that fits
        /// -75 bytes vs `.Closest`
        /// Initially faster to allocate but causes major fragmentation issues
        First,
    };

    pub const BuddyStrategy = enum {
        /// Return the raw free frame immediately
        /// Generally faster because it does not recombine or resplit frames,
        /// but it also requires more underlying memory
        Fast,

        /// Recombine with free buddies to reclaim storage
        /// +153 bytes vs `.Fast`
        /// More efficient use of existing memory at the cost of cycles and bytes
        Coalesce,
    };

    pub const ShrinkStrategy = enum {
        /// Return a smaller view into the same frame
        /// Faster because it ignores shrink, but never reclaims space until freed
        Defer,

        /// Split the frame into smallest usable chunk
        /// +112 bytes vs `.Defer`
        /// Better at reclaiming non-jumbo memory, but never reclaims jumbo until freed
        Chunkify,
    };

    pub const Validation = enum {
        /// Enable all validations, including library internals
        Dev,

        /// Only validate external boundaries — e.g. `realloc` or `free`
        External,

        /// Turn off all validations — pretend this library is `--release-small`
        Unsafe,

        fn useInternal(comptime self: Validation) bool {
            if (builtin.mode == .Debug) {
                return true;
            }
            return self == .Dev;
        }

        fn useExternal(comptime self: Validation) bool {
            return switch (builtin.mode) {
                .Debug => true,
                .ReleaseSafe => self == .Dev or self == .External,
                else => false,
            };
        }

        fn assertInternal(comptime self: Validation, ok: bool) void {
            @setRuntimeSafety(comptime self.useInternal());
            if (!ok) unreachable;
        }

        fn assertExternal(comptime self: Validation, ok: bool) void {
            @setRuntimeSafety(comptime self.useExternal());
            if (!ok) unreachable;
        }
    };
};

pub fn ZeeAlloc(comptime conf: Config) type {
    std.debug.assert(conf.page_size >= std.mem.page_size);
    std.debug.assert(std.math.isPowerOfTwo(conf.page_size));

    const inv_bitsize_ref = page_index + std.math.log2_int(usize, conf.page_size);
    const size_buckets = inv_bitsize_ref - std.math.log2_int(usize, min_frame_size) + 1; // + 1 jumbo list

    return struct {
        const Self = @This();

        const config = conf;

        // Synthetic representation -- should not be created directly, but instead carved out of []u8 bytes
        const Frame = packed struct {
            const alignment = 2 * @sizeOf(usize);
            const allocated_signal = @intToPtr(*Frame, std.math.maxInt(usize));

            next: ?*Frame,
            frame_size: usize,
            // We can't embed arbitrarily sized arrays in a struct so stick a placeholder here
            payload: [min_payload_size]u8,

            fn isCorrectSize(memsize: usize) bool {
                return memsize >= min_frame_size and (memsize % conf.page_size == 0 or std.math.isPowerOfTwo(memsize));
            }

            pub fn init(raw_bytes: []u8) *Frame {
                @setRuntimeSafety(comptime conf.validation.useInternal());
                const node = @ptrCast(*Frame, raw_bytes.ptr);
                node.frame_size = raw_bytes.len;
                node.validate() catch unreachable;
                return node;
            }

            pub fn restoreAddr(addr: usize) *Frame {
                @setRuntimeSafety(comptime conf.validation.useInternal());
                const node = @intToPtr(*Frame, addr);
                node.validate() catch unreachable;
                return node;
            }

            pub fn restorePayload(payload: [*]u8) !*Frame {
                @setRuntimeSafety(comptime conf.validation.useInternal());
                const node = @fieldParentPtr(Frame, "payload", @ptrCast(*[min_payload_size]u8, payload));
                try node.validate();
                return node;
            }

            pub fn validate(self: *Frame) !void {
                if (@ptrToInt(self) % alignment != 0) {
                    return error.UnalignedMemory;
                }
                if (!Frame.isCorrectSize(self.frame_size)) {
                    return error.UnalignedMemory;
                }
            }

            pub fn isAllocated(self: *Frame) bool {
                return self.next == allocated_signal;
            }

            pub fn markAllocated(self: *Frame) void {
                self.next = allocated_signal;
            }

            pub fn payloadSize(self: *Frame) usize {
                @setRuntimeSafety(comptime conf.validation.useInternal());
                return self.frame_size - meta_size;
            }

            pub fn payloadSlice(self: *Frame, start: usize, end: usize) []u8 {
                @setRuntimeSafety(comptime conf.validation.useInternal());
                conf.validation.assertInternal(start <= end);
                conf.validation.assertInternal(end <= self.payloadSize());
                const ptr = @ptrCast([*]u8, &self.payload);
                return ptr[start..end];
            }
        };

        const FreeList = packed struct {
            first: ?*Frame,

            pub fn init() FreeList {
                return FreeList{ .first = null };
            }

            pub fn root(self: *FreeList) *Frame {
                // Due to packed struct layout, FreeList.first == Frame.next
                // This enables more graceful iteration without needing a back reference.
                // Since this is not a full frame, accessing any other field will corrupt memory.
                // Thar be dragons 🐉
                return @ptrCast(*Frame, self);
            }

            pub fn prepend(self: *FreeList, node: *Frame) void {
                node.next = self.first;
                self.first = node;
            }

            pub fn remove(self: *FreeList, target: *Frame) !void {
                var iter = self.root();
                while (iter.next) |next| : (iter = next) {
                    if (next == target) {
                        _ = self.removeAfter(iter);
                        return;
                    }
                }

                return error.ElementNotFound;
            }

            pub fn removeAfter(self: *FreeList, ref: *Frame) *Frame {
                _ = self;
                const next_node = ref.next.?;
                ref.next = next_node.next;
                return next_node;
            }
        };



        backing_allocator: Allocator,

        free_lists: [size_buckets]FreeList = [_]FreeList{FreeList.init()} ** size_buckets,
        pub fn allocator(self: *Self) Allocator {
            return Allocator.init(self, alloc, resize, freeImpl);
        }
        fn freeImpl(ptr: *Self, buf: []u8, buf_align: u29, ret_addr: usize) void {
            _ = resize(ptr, buf, buf_align, 0, 0, ret_addr) ;
        }

        pub fn init(backing_allocator: Allocator) Self {
            return Self{ .backing_allocator = backing_allocator };
        }

        fn allocNode(self: *Self, memsize: usize) !*Frame {
            @setRuntimeSafety(comptime conf.validation.useInternal());
            const alloc_size = unsafeAlignForward(memsize + meta_size);
            const rawData = try self.backing_allocator.vtable.alloc(&self.backing_allocator, alloc_size, conf.page_size, 0, 0);
            return Frame.init(rawData);
        }

        fn findFreeNode(self: *Self, memsize: usize) ?*Frame {
            @setRuntimeSafety(comptime conf.validation.useInternal());
            var search_size = self.padToFrameSize(memsize);

            while (true) : (search_size *= 2) {
                const i = self.freeListIndex(search_size);
                var free_list = &self.free_lists[i];

                var closest_match_prev: ?*Frame = null;
                var closest_match_size: usize = std.math.maxInt(usize);

                var iter = free_list.root();
                while (iter.next) |next| : (iter = next) {
                    switch (conf.jumbo_match_strategy) {
                        .Exact => {
                            if (next.frame_size == search_size) {
                                return free_list.removeAfter(iter);
                            }
                        },
                        .Closest => {
                            if (next.frame_size == search_size) {
                                return free_list.removeAfter(iter);
                            } else if (next.frame_size > search_size and next.frame_size < closest_match_size) {
                                closest_match_prev = iter;
                                closest_match_size = next.frame_size;
                            }
                        },
                        .First => {
                            if (next.frame_size >= search_size) {
                                return free_list.removeAfter(iter);
                            }
                        },
                    }
                }

                if (closest_match_prev) |prev| {
                    return free_list.removeAfter(prev);
                }

                if (i <= page_index) {
                    return null;
                }
            }
        }

        fn chunkify(self: *Self, node: *Frame, target_size: usize, len_align: u29) usize {
            @setCold(config.shrink_strategy != .Defer);
            @setRuntimeSafety(comptime conf.validation.useInternal());
            conf.validation.assertInternal(target_size <= node.payloadSize());

            if (node.frame_size <= conf.page_size) {
                const target_frame_size = self.padToFrameSize(target_size);

                var sub_frame_size = node.frame_size / 2;
                while (sub_frame_size >= target_frame_size) : (sub_frame_size /= 2) {
                    const start = node.payloadSize() - sub_frame_size;
                    const sub_frame_data = node.payloadSlice(start, node.payloadSize());
                    const sub_node = Frame.init(sub_frame_data);
                    self.freeListOfSize(sub_frame_size).prepend(sub_node);
                    node.frame_size = sub_frame_size;
                }
            }

            return std.mem.alignAllocLen(node.payloadSize(), target_size, len_align);
        }

        fn free(self: *Self, target: *Frame) void {
            @setCold(true);
            @setRuntimeSafety(comptime conf.validation.useInternal());
            var node = target;
            if (conf.buddy_strategy == .Coalesce) {
                while (node.frame_size < conf.page_size) : (node.frame_size *= 2) {
                    // 16: [0, 16], [32, 48]
                    // 32: [0, 32], [64, 96]
                    const node_addr = @ptrToInt(node);
                    const buddy_addr = node_addr ^ node.frame_size;

                    const buddy = Frame.restoreAddr(buddy_addr);
                    if (buddy.isAllocated() or buddy.frame_size != node.frame_size) {
                        break;
                    }

                    self.freeListOfSize(buddy.frame_size).remove(buddy) catch unreachable;

                    // Use the lowest address as the new root
                    node = Frame.restoreAddr(node_addr & buddy_addr);
                }
            }

            self.freeListOfSize(node.frame_size).prepend(node);
        }

        // https://github.com/ziglang/zig/issues/2426
        fn unsafeCeilPowerOfTwo(comptime T: type, value: T) T {
            @setRuntimeSafety(comptime conf.validation.useInternal());
            if (value <= 2) return value;
            const Shift = comptime std.math.Log2Int(T);
            return @as(T, 1) << @intCast(Shift, @bitSizeOf(T) - @clz(T, value - 1));
        }

        fn unsafeLog2Int(comptime T: type, x: T) std.math.Log2Int(T) {
            @setRuntimeSafety(comptime conf.validation.useInternal());
            conf.validation.assertInternal(x != 0);
            return @intCast(std.math.Log2Int(T), @bitSizeOf(T) - 1 - @clz(T, x));
        }

        fn unsafeAlignForward(size: usize) usize {
            @setRuntimeSafety(comptime conf.validation.useInternal());
            const forward = size + (conf.page_size - 1);
            return forward & ~(conf.page_size - 1);
        }

        fn padToFrameSize(self: *Self, memsize: usize) usize {
            _ = self;
            @setRuntimeSafety(comptime conf.validation.useInternal());
            const meta_memsize = std.math.max(memsize + meta_size, min_frame_size);
            return std.math.min(unsafeCeilPowerOfTwo(usize, meta_memsize), unsafeAlignForward(meta_memsize));
            // More byte-efficient of this:
            // const meta_memsize = memsize + meta_size;
            // if (meta_memsize <= min_frame_size) {
            //     return min_frame_size;
            // } else if (meta_memsize < conf.page_size) {
            //     return ceilPowerOfTwo(usize, meta_memsize);
            // } else {
            //     return std.mem.alignForward(meta_memsize, conf.page_size);
            // }
        }

        fn freeListOfSize(self: *Self, frame_size: usize) *FreeList {
            _ = self;
            @setRuntimeSafety(comptime conf.validation.useInternal());
            const i = self.freeListIndex(frame_size);
            return &self.free_lists[i];
        }

        fn freeListIndex(self: *Self, frame_size: usize) usize {
            _ = self;
            @setRuntimeSafety(comptime conf.validation.useInternal());
            conf.validation.assertInternal(Frame.isCorrectSize(frame_size));
            return inv_bitsize_ref - std.math.min(inv_bitsize_ref, unsafeLog2Int(usize, frame_size));
            // More byte-efficient of this:
            // if (frame_size > conf.page_size) {
            //     return jumbo_index;
            // } else if (frame_size <= min_frame_size) {
            //     return self.free_lists.len - 1;
            // } else {
            //     return inv_bitsize_ref - unsafeLog2Int(usize, frame_size);
            // }
        }

        fn alloc(self: *Self, n: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Allocator.Error![]u8 {
            _ = ret_addr;
            if (ptr_align > min_frame_size) {
                return error.OutOfMemory;
            }

            const node = self.findFreeNode(n) orelse try self.allocNode(n);
            node.markAllocated();
            const len = self.chunkify(node, n, len_align);
            return node.payloadSlice(0, len);
        }

        fn resize(self: *Self, buf: []u8, buf_align: u29, new_size: usize, len_align: u29, ret_addr: usize) ?usize {
            _ = ret_addr;
            _ = buf_align;
            @setRuntimeSafety(comptime conf.validation.useExternal());
            const node = Frame.restorePayload(buf.ptr) catch unreachable;
            conf.validation.assertExternal(node.isAllocated());
            if (new_size == 0) {
                self.free(node);
                return 0;
            } else if (new_size > node.payloadSize()) {
                return null;
            } else switch (conf.shrink_strategy) {
                .Defer => return new_size,
                .Chunkify => return self.chunkify(node, new_size, len_align),
            }
        }

        fn debugCount(self: *Self, index: usize) usize {
            var count: usize = 0;
            var iter = self.free_lists[index].first;
            while (iter) |node| : (iter = node.next) {
                count += 1;
            }
            return count;
        }

        fn debugCountAll(self: *Self) usize {
            var count: usize = 0;
            for (self.free_lists) |_, i| {
                count += self.debugCount(i);
            }
            return count;
        }

        fn debugDump(self: *Self) void {
            for (self.free_lists) |_, i| {
                std.debug.warn("{}: {}\n", i, self.debugCount(i));
            }
        }
    };
}

fn assertIf(comptime run_assert: bool, ok: bool) void {
    @setRuntimeSafety(run_assert);
    if (!ok) unreachable;
}
