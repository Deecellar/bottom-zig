//! # Bottom-zig
//! A Zig implementation of the Bottom encoding specification
//!
//! This program provides encoding and decoding capabilities for the Bottom text format,
//! which converts regular text into a series of bottom-speak emojis.
//!
//! ## Usage
//! ```
//! bottom-zig -b "text"  # Encode text to bottom
//! bottom-zig -r "🥺👉👈"  # Decode bottom to text
//! ```

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const args = @import("zig-args");
const bottom = @import("bottom");

const help_text = @embedFile("help.txt");

/// Maximum buffer size for reading/writing operations (128KB)
const bufferSize = 128 * 1024;

/// Platform-specific newline character
const newline = if (builtin.os.tag == .windows) "\r\n" else "\n";

const scoped = std.log.scoped(.BottomCliProgram);

/// Command line options for the program
/// Provides configuration for encoding/decoding operations
const Options = struct {
    /// Convert text to bottom encoding
    bottomify: bool = false,

    /// Display help information
    help: bool = false,

    /// Convert bottom encoding back to text
    regress: bool = false,

    /// Display version information
    version: bool = false,

    /// Input file path (optional)
    input: ?[]const u8 = null,

    /// Output file path (optional)
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

/// Program-specific error types
const BottomZigErrors = error{
    /// Windows console does not support UTF-8 encoding
    windows_unsuported_code_page,

    /// Failed to parse command line arguments
    failed_args_parsing,

    /// Neither bottomify nor regress was specified
    obligatory_arguments_not_provided,

    /// Multiple exclusive operations specified
    exclusive_arguments_provided,

    /// Could not open the specified input file
    failed_to_open_input_file,

    /// Could not open/create the specified output file
    failed_to_open_output_file,

    /// Failed to write data to output file
    failed_to_flush_into_file,

    /// Invalid bottom encoding detected
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
    errors_to_report: std.DoublyLinkedList(BottomZigErrors),
    node_array: [1024]std.DoublyLinkedList(BottomZigErrors).Node,
    index: usize,
    exit_code: ExitCode = .{},
    pub fn init() BottomErrorHandler {
        return .{
            .errors_to_report = std.DoublyLinkedList(BottomZigErrors){},
            .node_array = .{std.DoublyLinkedList(BottomZigErrors).Node{ .data = error.exclusive_arguments_provided, .next = null, .prev = null }} ** 1024,
            .index = 0,
        };
    }
    pub fn report(self: *BottomErrorHandler, err: BottomZigErrors) void {
        self.node_array[self.index] = std.DoublyLinkedList(BottomZigErrors).Node{ .data = err, .next = null, .prev = null };
        if (self.index > 0) self.node_array[self.index].prev = &self.node_array[self.index - 1];
        self.errors_to_report.append(&self.node_array[self.index]);
        if (@atomicRmw(usize, &self.index, std.builtin.AtomicRmwOp.Add, 1, std.builtin.AtomicOrder.seq_cst) > self.node_array.len) {
            _ = @atomicRmw(usize, &self.index, std.builtin.AtomicRmwOp.Sub, 1, std.builtin.AtomicOrder.seq_cst);
            // We are trunctating the stack, this is not a problem because we are only reporting errors
        }
    }

    pub fn handleErrors(self: *BottomErrorHandler) void {
        while (self.errors_to_report.pop()) |node| {
            switch (node.data) {
                error.windows_unsuported_code_page => {
                    scoped.err("UTF-8 encoding not supported by your Windows console.\nPlease install Windows Terminal: https://aka.ms/terminal\nOr enable UTF-8 support in your current console.", .{});
                    self.exit_code.windows_unsuported_code_page = 1;
                },
                error.failed_args_parsing => {
                    scoped.err("Invalid command line arguments.\nUsage: bottom-zig (-b|--bottomify) <text> or (-r|--regress) <bottom-text>\nUse -h or --help for detailed instructions.", .{});
                    self.exit_code.failed_args_parsing = 1;
                },
                error.obligatory_arguments_not_provided => {
                    scoped.err("Missing required operation flag >_<\nPlease specify either:\n  -b/--bottomify to encode text\n  -r/--regress to decode bottom encoding", .{});
                    self.exit_code.obligatory_arguments_not_provided = 1;
                },
                error.exclusive_arguments_provided => {
                    scoped.err("Multiple exclusive operations specified!\nUse only one of:\n  --bottomify (-b)\n  --regress (-r)\n  --version (-V)", .{});
                    self.exit_code.exclusive_arguments_provided = 1;
                },
                error.failed_to_open_input_file => {
                    scoped.err("Cannot open input file!\nPlease check:\n- File exists\n- You have read permissions\n- Path is correct\n- Disk is not corrupted", .{});
                    self.exit_code.failed_to_open_input_file = 1;
                },
                error.failed_to_open_output_file => {
                    scoped.err("Cannot create/open output file!\nPlease check:\n- You have write permissions\n- Directory exists\n- Disk has enough space\n- Path is valid", .{});
                    self.exit_code.failed_to_open_output_file = 1;
                },
                error.failed_to_flush_into_file => {
                    scoped.err("Failed to write to output file!\nPossible causes:\n- Insufficient disk space\n- Lost write permissions\n- Disk error occurred\n- File system is read-only", .{});
                    self.exit_code.failed_to_flush_into_file = 1;
                },
                error.failed_to_decode_byte => {
                    scoped.err("Invalid bottom encoding detected!\nPlease ensure the input is valid bottom-encoded text\nExample valid format: 🥺👉👈", .{});
                    self.exit_code.failed_to_decode_byte = 1;
                },
            }
        }
    }

    pub fn exit(self: *BottomErrorHandler) noreturn {
        std.posix.exit(@bitCast(self.exit_code));
    }

    pub fn deinit(self: *BottomErrorHandler) noreturn {
        if (!(self.errors_to_report.len == 0)) self.handleErrors();
        self.exit();
    }
};

/// Handles program operations and file I/O
/// Manages the lifecycle of encoding/decoding operations
const BottomConsoleApp = struct {
    err_handler: BottomErrorHandler,
    options: Options,
    input_file: std.fs.File,
    output_file: std.fs.File,

    /// Initialize the console application
    /// Params:
    ///   options: Parsed command line options
    /// Returns: Configured BottomConsoleApp instance
    pub fn init(options: Options) BottomConsoleApp {
        var can_use_stdin_stdout: bool = true;
        var err_handler = BottomErrorHandler.init();
        if (builtin.os.tag == .windows) {
            if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
                can_use_stdin_stdout = false;
                err_handler.report(error.windows_unsuported_code_page); // if this fails, stdin and stdout will be broken, on usage of these two, an error will be reported
            }
        }
        const dummy_file = std.io.getStdOut();
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
        if ((options.version and (options.bottomify or options.regress)) or options.bottomify and options.regress) {
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

    /// Execute the requested operation based on provided options
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

    /// Convert input text to bottom encoding
    /// Reads from input_file and writes encoded result to output_file
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
            const outbuffer: []u8 = bottom.encoder.encode(stdin_buffer[0 .. stdin_buffer.len - (newline.len - 1)], &bufferBottom);
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
                const outbuffer: []u8 = bottom.encoder.encode(buffer[0 .. size - 1], &bufferBottom);
                bufferOut.writer().writeAll(outbuffer) catch {
                    self.err_handler.report(error.failed_to_open_output_file);
                    return;
                };
                buffer = undefined;
                bufferBottom = undefined;
            }
        }
    }

    /// Display help information
    pub fn help(self: *BottomConsoleApp) void {
        std.io.getStdOut().writer().writeAll(help_text) catch {
            self.err_handler.report(error.failed_to_flush_into_file);
        };
    }

    /// Display version information
    pub fn version(self: *BottomConsoleApp) void {
        std.io.getStdOut().writer().writeAll(build_options.version) catch {
            self.err_handler.report(error.failed_to_flush_into_file);
        };
    }

    /// Convert bottom encoding back to text
    /// Reads from input_file and writes decoded result to output_file
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
            const outbuffer: []u8 = bottom.decoder.decode(stdin_buffer[0 .. stdin_buffer.len - (newline.len - 1)], bufferRegress[0 .. (buffer.len / bottom.encoder.max_expansion_per_byte - 1) * 2]) catch {
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
                const textToSplit = "👉👈";
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
                const outbuffer: u8 = bottom.decoder.decodeByte(temp) orelse {
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

    /// Clean up resources and exit
    pub fn deinit(self: *BottomConsoleApp) noreturn {
        self.err_handler.deinit();
    }
};

pub fn main() noreturn {
    var app = init_blk: {
        const underlying_allocator = allocator_blk: {
            if (builtin.mode != .Debug) {
                break :allocator_blk std.heap.smp_allocator;
            } else {
                var gpa = std.heap.DebugAllocator(.{}){};
                break :allocator_blk gpa.allocator();
            }
        };
        var thread_safe_allocator = std.heap.ThreadSafeAllocator{ .child_allocator = underlying_allocator };
        const allocator = thread_safe_allocator.allocator();
        var options = args.parseForCurrentProcess(Options, allocator, .print) catch {
            scoped.err("Failed to get memory for options", .{});
            std.posix.exit(3);
        };
        const op = options.options;
        defer options.deinit();
        break :init_blk BottomConsoleApp.init(op);
    };
    app.run();
    app.deinit();
}
