const std = @import("std");
const bottom = @import("bottom");
const args = @import("zig-args");
const builtin = @import("builtin");
const build_options = @import("build_options");
const help_text = @embedFile("help.txt");
const bufferSize = 128 * 1024;
const newline = if (builtin.os.tag == .windows) "\r\n" else "\n";
const scoped = std.log.scoped(.BottomCliProgram);

/// We create options similar to bottom RS
const Options = struct {
    bottomify: bool = false,
    help: bool = false,
    regress: bool = false,
    version: bool = false,
    input: ?[]const u8 = null,
    output: ?[]const u8 = null,
    pub const shorthands = .{
        .b = "bottomify",
        .h = "help",
        .r = "regress",
        .V = "version",
        .i = "input",
        .o = "output",
    };
};

const BottomZigErrors = error{
    windows_unsuported_code_page,
    failed_args_parsing,
    obligatory_arguments_not_provided,
    exclusive_arguments_provided,
    failed_to_open_input_file,
    failed_to_open_output_file,
    failed_to_flush_into_file,
    failed_to_decode_byte,
};

const ExitCode = packed struct {
    windows_unsuported_code_page: u1 = 0,
    failed_args_parsing: u1 = 0,
    obligatory_arguments_not_provided: u1 = 0,
    exclusive_arguments_provided: u1 = 0,
    failed_to_open_input_file: u1 = 0,
    failed_to_open_output_file: u1 = 0,
    failed_to_flush_into_file: u1 = 0,
    failed_to_decode_byte: u1 = 0,

    pub inline fn toInt(self: ExitCode) u8 {
        return @bitCast(self);
    }
};

const BottomErrorHandler = struct {
    errors_to_report: std.atomic.Stack(BottomZigErrors),
    node_array: [1024]std.atomic.Stack(BottomZigErrors).Node,
    index: usize,
    exit_code: ExitCode = .{},
    pub fn init() BottomErrorHandler {
        return .{
            .errors_to_report = std.atomic.Stack(BottomZigErrors).init(),
            .node_array = .{std.atomic.Stack(BottomZigErrors).Node{ .data = error.exclusive_arguments_provided, .next = null }} ** 1024,
            .index = 0,
        };
    }
    pub fn report(self: *BottomErrorHandler, err: BottomZigErrors) void {
        self.node_array[self.index] = std.atomic.Stack(BottomZigErrors).Node{ .data = err, .next = null };
        self.errors_to_report.push(&self.node_array[self.index]);
        if (@atomicRmw(usize, &self.index, std.builtin.AtomicRmwOp.Add, 1, std.builtin.AtomicOrder.SeqCst) > self.node_array.len) {
            _ = @atomicRmw(usize, &self.index, std.builtin.AtomicRmwOp.Sub, 1, std.builtin.AtomicOrder.SeqCst);
            // We are trunctating the stack, this is not a problem because we are only reporting errors
        }
    }

    pub fn handleErrors(self: *BottomErrorHandler) void {
        while (self.errors_to_report.pop()) |node| {
            switch (node.data) {
                error.windows_unsuported_code_page => {
                    scoped.err("Your windows console does not support UTF-8, try using Windows Terminal at: {s}", .{"https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701?hl=en-us&gl=US"});
                    self.exit_code.windows_unsuported_code_page = 1;
                },
                error.failed_args_parsing => {
                    scoped.err("Failed to parse arguments, please check your arguments and try again", .{});
                    self.exit_code.failed_args_parsing = 1;
                },
                error.obligatory_arguments_not_provided => {
                    scoped.err("You have to specify either bottomify or regress OwO", .{});
                    self.exit_code.obligatory_arguments_not_provided = 1;
                },
                error.exclusive_arguments_provided => {
                    scoped.err("You cannot use both bottomify and regress UwU", .{});
                    self.exit_code.exclusive_arguments_provided = 1;
                },
                error.failed_to_open_input_file => {
                    scoped.err("Failed to open input file, please check your arguments, check you have read access or if your disk is not corrupt", .{});
                    self.exit_code.failed_to_open_input_file = 1;
                },
                error.failed_to_open_output_file => {
                    scoped.err("Failed to open output file, please check your arguments, check you have write access or if your disk is not corrupt or full", .{});
                    self.exit_code.failed_to_open_output_file = 1;
                },
                error.failed_to_flush_into_file => {
                    scoped.err("Failed to flush into output file, please check you have write access, your file is not corrupt, your disk is not full", .{});
                    self.exit_code.failed_to_flush_into_file = 1;
                },
                error.failed_to_decode_byte => {
                    scoped.err("Failed to decode byte, please provide a valid bottom file", .{});
                    self.exit_code.failed_to_decode_byte = 1;
                },
            }
        }
    }

    pub fn exit(self: *BottomErrorHandler) noreturn {
        std.os.exit(@bitCast(self.exit_code));
    }

    pub fn deinit(self: *BottomErrorHandler) noreturn {
        if (!self.errors_to_report.isEmpty()) self.handleErrors();
        self.exit();
    }
};

const BottomConsoleApp = struct {
    err_handler: BottomErrorHandler,
    options: Options,
    input_file: std.fs.File,
    output_file: std.fs.File,

    pub fn init(options: Options) BottomConsoleApp {
        var can_use_stdin_stdout: bool = true;
        var err_handler = BottomErrorHandler.init();
        if (builtin.os.tag == .windows) {
            if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
                can_use_stdin_stdout = false;
                err_handler.report(error.windows_unsuported_code_page); // if this fails, stdin and stdout will be broken, on usage of these two, an error will be reported
            }
        }
        var dummy_file = std.io.getStdOut();
        // we try to open the input file
        var input_file: std.fs.File = undefined;
        if (options.input) |path| {
            input_file = std.fs.cwd().openFile(path, .{}) catch file_return: {
                err_handler.report(error.failed_to_open_input_file);
                break :file_return dummy_file;
            };
        } else if (can_use_stdin_stdout) {
            input_file = std.io.getStdIn();
        } else {
            err_handler.report(error.failed_to_open_input_file);
        }
        // we try to open the output file
        var output_file: std.fs.File = undefined;
        if (options.output) |path| {
            output_file = std.fs.cwd().createFile(path, .{}) catch file_return: {
                err_handler.report(error.failed_to_open_output_file);
                break :file_return dummy_file;
            };
        } else if (can_use_stdin_stdout) {
            output_file = std.io.getStdOut();
        } else {
            err_handler.report(error.failed_to_open_output_file);
        }

        // Version, bottomify and regress are mutually exclusive
        if (options.version and (options.bottomify or options.regress)) {
            err_handler.report(error.exclusive_arguments_provided);
        }
        // At least one of the options must be provided
        if (!options.help and !options.version and !options.bottomify and !options.regress) {
            err_handler.report(error.obligatory_arguments_not_provided);
        }
        err_handler.handleErrors();
        if (err_handler.exit_code.toInt() != 0) {
            err_handler.exit();
        }
        return .{
            .err_handler = err_handler,
            .options = options,
            .input_file = input_file,
            .output_file = output_file,
        };
    }

    pub fn run(self: *BottomConsoleApp) void {
        if (self.options.help) {
            self.help();
        } else if (self.options.bottomify) {
            self.bottomify();
        } else if (self.options.regress) {
            self.regress();
        } else if (self.options.version) {
            self.version();
        } else {
            unreachable;
        }
    }

    pub fn bottomify(self: *BottomConsoleApp) void {
        var bufferInput: std.io.BufferedReader(bufferSize, std.fs.File.Reader) = .{ .unbuffered_reader = self.input_file.reader() };
        var bufferOut: std.io.BufferedWriter(bufferSize * bottom.encoder.max_expansion_per_byte, std.fs.File.Writer) = .{ .unbuffered_writer = self.output_file.writer() };
        var bufferBottom: [bufferSize * bottom.encoder.max_expansion_per_byte]u8 = undefined;
        var buffer: [bufferSize]u8 = undefined;
        var size: usize = 1;
        defer bufferOut.flush() catch {
            self.err_handler.report(error.failed_to_flush_into_file);
        };
        if (self.input_file.handle == std.io.getStdIn().handle) {
            var stdin_buffer = bufferInput.reader().readUntilDelimiter(&buffer, '\n') catch {
                self.err_handler.report(error.failed_to_open_input_file);
                return;
            };
            var outbuffer: []u8 = bottom.encoder.encode(stdin_buffer[0 .. stdin_buffer.len - (newline.len - 1)], &bufferBottom);
            _ = bufferOut.writer().writeAll(outbuffer) catch {
                self.err_handler.report(error.failed_to_flush_into_file);
                return;
            };
            if (self.output_file.handle == std.io.getStdOut().handle) {
                _ = bufferOut.writer().write(newline) catch {
                    self.err_handler.report(error.failed_to_flush_into_file);
                    return;
                };
            }
            buffer = undefined;
            bufferBottom = undefined;
            return;
        }
        while (size != 0) {
            size = bufferInput.read(&buffer) catch {
                self.err_handler.report(error.failed_to_open_input_file);
                return;
            };
            if (size > 0) {
                var outbuffer: []u8 = bottom.encoder.encode(buffer[0 .. size - 1], &bufferBottom);
                bufferOut.writer().writeAll(outbuffer) catch {
                    self.err_handler.report(error.failed_to_open_output_file);
                    return;
                };
                buffer = undefined;
                bufferBottom = undefined;
            }
        }
    }

    pub fn help(self: *BottomConsoleApp) void {
        std.io.getStdOut().writer().writeAll(help_text) catch {
            self.err_handler.report(error.failed_to_flush_into_file);
        };
    }

    pub fn version(self: *BottomConsoleApp) void {
        std.io.getStdOut().writer().writeAll(build_options.version) catch {
            self.err_handler.report(error.failed_to_flush_into_file);
        };
    }

    pub fn regress(self: *BottomConsoleApp) void {
        var bufferInput: std.io.BufferedReader(bufferSize, std.fs.File.Reader) = .{ .unbuffered_reader = self.input_file.reader() };
        var bufferOut: std.io.BufferedWriter(bufferSize * bottom.encoder.max_expansion_per_byte, std.fs.File.Writer) = .{ .unbuffered_writer = self.output_file.writer() };
        var bufferRegress: [bufferSize * bottom.encoder.max_expansion_per_byte]u8 = undefined;
        var buffer: [bufferSize]u8 = undefined;
        var temp: []const u8 = &@as([1]u8, undefined);
        defer bufferOut.flush() catch {
            self.err_handler.report(error.failed_to_flush_into_file);
        };
        if (self.input_file.handle == std.io.getStdIn().handle) {
            var stdin_buffer = bufferInput.reader().readUntilDelimiter(&buffer, '\n') catch {
                self.err_handler.report(error.failed_to_open_input_file);
                return;
            };
            var outbuffer: []u8 = bottom.decoder.decode(stdin_buffer[0 .. stdin_buffer.len - (newline.len - 1)], bufferRegress[0 .. (buffer.len / bottom.encoder.max_expansion_per_byte - 1) * 2]) catch {
                self.err_handler.report(error.failed_to_flush_into_file);
                return;
            };
            _ = bufferOut.writer().writeAll(outbuffer) catch {
                self.err_handler.report(error.failed_to_flush_into_file);
                return;
            };
            if (self.output_file.handle == std.io.getStdOut().handle) {
                _ = bufferOut.writer().write(newline) catch {
                    self.err_handler.report(error.failed_to_flush_into_file);
                    return;
                };
            }
            buffer = undefined;
            bufferRegress = undefined;
            return;
        }
        while (temp.len != 0) {
            temp = temp_calculate_block: {
                // We read until we find 👉👈 , we need to do this manually because readUntilDelimiter is per byte not per slice
                var textToSplit = "👉👈";
                var result: [40]u8 = std.mem.zeroes([40]u8);
                var result_index: usize = 0;
                while (bufferInput.reader().readByte() catch null) |r| {
                    result[result_index] = r;
                    result_index += 1;
                    // We read 1 byte, we check that the last 8 bytes are not 👉👈, and we add the byte to the result,
                    // if the last 8 bytes are 👉👈 we break the loop
                    if (result_index >= 8) {
                        var is_emoji: bool = true;
                        inline for (textToSplit, 0..) |c, i| {
                            if (result[result_index - (textToSplit.len - i)] != c) {
                                is_emoji = false;
                                break;
                            }
                        }
                        if (is_emoji) {
                            break :temp_calculate_block result[0 .. result_index - textToSplit.len];
                        }
                    }
                }
                break :temp_calculate_block &@as([0]u8, undefined);
            };

            if (temp.len > 0) {
                var outbuffer: u8 = bottom.decoder.decodeByte(temp) orelse {
                    self.err_handler.report(error.failed_to_decode_byte);
                    return;
                };
                _ = bufferOut.writer().writeByte(outbuffer) catch {
                    self.err_handler.report(error.failed_to_flush_into_file);
                    return;
                };
                buffer = undefined;
                bufferRegress = undefined;
            }
        }
    }

    pub fn deinit(self: *BottomConsoleApp) noreturn {
        self.err_handler.deinit();
    }
};

pub fn main() noreturn {
    var app = init_blk: {
        var underlying_allocator = allocator_blk: {
            if (build_options.use_c) {
                break :allocator_blk std.heap.c_allocator;
            } else {
                var gpa = std.heap.GeneralPurposeAllocator(.{}){};
                break :allocator_blk gpa.allocator();
            }
        };
        var thread_safe_allocator = std.heap.ThreadSafeAllocator{ .child_allocator = underlying_allocator };
        var allocator = thread_safe_allocator.allocator();
        var options = args.parseForCurrentProcess(Options, allocator, .print) catch {
            scoped.err("Failed to get memory for options", .{});
            std.os.exit(3);
        };
        var op = options.options;
        defer options.deinit();
        break :init_blk BottomConsoleApp.init(op);
    };
    app.run();
    app.deinit();
}
