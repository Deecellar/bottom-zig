//! # Bottom CLI - Command-line encoder/decoder for Bottom text encoding
//!
//! Provides stdin/stdout and file-based encoding/decoding with comprehensive
//! error handling and cross-platform UTF-8 support. Supports the Bottom emoji
//! encoding format (https://github.com/bottom-software-foundation/bottom-spec).

const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const build_options = @import("build_options");

const bottom = @import("bottom");

const help_text = @embedFile("help.txt");

// 128KB buffer size for input/output operations.
const bufferSize = 128 * 1024;

// Maximum encoding expansion: byte 200 (✨✨✨,,,) expands to 48 bytes.
// This is the worst-case for any single byte in the Bottom encoding scheme.
const max_expansion_per_byte = 48;

const newline = if (builtin.os.tag == .windows) "\r\n" else "\n";

const scoped = std.log.scoped(.BottomCliProgram);

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
    const ErrorNode = struct {
        data: BottomZigErrors,
        node: std.DoublyLinkedList.Node = .{},
    };

    errors_to_report: std.DoublyLinkedList,
    // Fixed-size array to avoid dynamic allocation. 1024 errors should be
    // sufficient for any reasonable CLI session. Atomically indexed for
    // thread-safety in case of concurrent error reporting.
    node_array: [1024]ErrorNode,
    index: usize,
    exit_code: ExitCode = .{},
    
    pub fn init() BottomErrorHandler {
        return .{
            .errors_to_report = .{},
            .node_array = @splat(ErrorNode{
                .data = error.exclusive_arguments_provided,
            }),
            .index = 0,
        };
    }
    
    pub fn report(self: *BottomErrorHandler, err: BottomZigErrors) void {
        self.node_array[self.index].data = err;
        self.errors_to_report.append(&self.node_array[self.index].node);
        if (@atomicRmw(usize, &self.index, std.builtin.AtomicRmwOp.Add, 1, std.builtin.AtomicOrder.seq_cst) > self.node_array.len) {
            _ = @atomicRmw(usize, &self.index, std.builtin.AtomicRmwOp.Sub, 1, std.builtin.AtomicOrder.seq_cst);
        }
    }

    pub fn handleErrors(self: *BottomErrorHandler) void {
        while (self.errors_to_report.pop()) |node| {
            const error_node: *ErrorNode = @fieldParentPtr("node", node);
            switch (error_node.data) {
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
    pub fn exitCode(self: *BottomErrorHandler) u8 {
        return @bitCast(self.exit_code);
    }

    pub fn deinit(self: *BottomErrorHandler) u8 {
        if (self.errors_to_report.len() != 0) self.handleErrors();
        return self.exitCode();
    }
 };

const BottomConsoleApp = struct {
    err_handler: BottomErrorHandler,
    options: Options,
    io: Io,
    input_file: Io.File,
    output_file: Io.File,

    pub fn init(io: Io, options: Options) BottomConsoleApp {
        var can_use_stdin_stdout: bool = true;
        var err_handler = BottomErrorHandler.init();
        if (builtin.os.tag == .windows) {
            if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
                can_use_stdin_stdout = false;
                err_handler.report(error.windows_unsuported_code_page);
            }
        }
        const dummy_file = Io.File.stdout();

        var input_file: Io.File = undefined;
        if (options.input) |path| {
            input_file = Io.Dir.cwd().openFile(io, path, .{}) catch file_return: {
                err_handler.report(error.failed_to_open_input_file);
                break :file_return dummy_file;
            };
        } else if (can_use_stdin_stdout) {
            input_file = Io.File.stdin();
        } else {
            err_handler.report(error.failed_to_open_input_file);
        }

        var output_file: Io.File = undefined;
        if (options.output) |path| {
            output_file = Io.Dir.cwd().createFile(io, path, .{}) catch file_return: {
                err_handler.report(error.failed_to_open_output_file);
                break :file_return dummy_file;
            };
        } else if (can_use_stdin_stdout) {
            output_file = Io.File.stdout();
        } else {
            err_handler.report(error.failed_to_open_output_file);
        }

        // Validate mutually exclusive flags before proceeding. The user should
        // specify exactly one operation: --version, --bottomify, or --regress.
        // --help can be combined with anything and takes precedence.
        if ((options.version and (options.bottomify or options.regress)) or options.bottomify and options.regress) {
            err_handler.report(error.exclusive_arguments_provided);
        }
        if (!options.help and !options.version and !options.bottomify and !options.regress) {
            err_handler.report(error.obligatory_arguments_not_provided);
        }
        err_handler.handleErrors();
        return .{
            .err_handler = err_handler,
            .options = options,
            .io = io,
            .input_file = input_file,
            .output_file = output_file,
        };
    }

    pub fn run(self: *BottomConsoleApp) void {
        if (self.options.help) {
            self.help();
        } else if (self.options.bottomify) {
            if (self.output_file.handle == Io.File.stdout().handle) {
                scoped.warn("Using standard input/output for encoding/decoding may cause issues if your console does not fully support UTF-8. If you encounter problems, consider using file-based input/output with the -i and -o options.", .{});
                scoped.info("Continuing with standard input/output...", .{});
                scoped.info("To finish the input use Ctrl + D (Linux/Mac) or Ctrl + Z (Windows) followed by Enter.", .{});
            }
            self.bottomify();
        } else if (self.options.regress) {
            if (self.input_file.handle == Io.File.stdin().handle) {
                scoped.warn("Using standard input/output for encoding/decoding may cause issues if your console does not fully support UTF-8. If you encounter problems, consider using file-based input/output with the -i and -o options.", .{});
                scoped.info("Continuing with standard input/output...", .{});
                scoped.info("To finish the input use Ctrl + D (Linux/Mac) or Ctrl + Z (Windows) followed by Enter.", .{});
            }
            self.regress();
        } else if (self.options.version) {
            self.version();
        } else {
            unreachable;
        }
    }

    pub fn bottomify(self: *BottomConsoleApp) void {
        var input_buffer: [bufferSize]u8 = undefined;
        var output_buffer: [bufferSize * max_expansion_per_byte]u8 = undefined;
        var encode_buffer: [bufferSize * max_expansion_per_byte]u8 = undefined;

        var input_reader = Io.File.Reader.init(self.input_file, self.io, &input_buffer);
        var output_writer = Io.File.Writer.init(self.output_file, self.io, &output_buffer);

        var encoder = bottom.BottomWriter.init(&encode_buffer, &output_writer.interface);

        defer output_writer.interface.flush() catch {
            self.err_handler.report(error.failed_to_flush_into_file);
        };

        _ = input_reader.interface.streamRemaining(&encoder.writer) catch {
            self.err_handler.report(error.failed_to_open_input_file);
            return;
        };

        encoder.writer.flush() catch {
            self.err_handler.report(error.failed_to_flush_into_file);
            return;
        };
    }

    pub fn help(self: *BottomConsoleApp) void {
        var stdout_writer = Io.File.stdout().writer(self.io, &help_buf);
        stdout_writer.interface.writeAll(help_text) catch return;
        stdout_writer.interface.flush() catch return;
    }

    pub fn version(self: *BottomConsoleApp) void {
        var stdout_writer = Io.File.stdout().writer(self.io, &help_buf);
        stdout_writer.interface.writeAll(build_options.version) catch return;
        stdout_writer.interface.flush() catch return;
    }

    pub fn regress(self: *BottomConsoleApp) void {
        // FIXME: Figure out the buffers sizes here
        var input_buffer: [bufferSize]u8 = undefined;
        var output_buffer: [bufferSize]u8 = undefined;
        var decode_buffer: [bufferSize]u8 = undefined;
        var encoded_buffer: [bufferSize]u8 = undefined;

        var input_reader = Io.File.Reader.init(self.input_file, self.io, &input_buffer);
        var output_writer = Io.File.Writer.init(self.output_file, self.io, &output_buffer);

        var decoder = bottom.BottomReader.init(&decode_buffer, &encoded_buffer, &input_reader.interface);

        defer output_writer.interface.flush() catch {
            self.err_handler.report(error.failed_to_flush_into_file);
        };

        _ = decoder.reader.streamRemaining(&output_writer.interface) catch {
            self.err_handler.report(error.failed_to_decode_byte);
            return;
        };
    }

    pub fn deinit(self: *BottomConsoleApp) u8 {
        return self.err_handler.deinit();
    }
};

var help_buf: [256]u8 = undefined;

/// Inline arg parser: handles long options (`--name value`, `--name=value`)
/// and shorthand clusters (`-bri foo`). No external dependency; matches the
/// subset of zig-args we previously used.
fn parseOptions(init: std.process.Init) !Options {
    const arena = init.arena.allocator();
    var it = try init.minimal.args.iterateAllocator(arena);
    defer it.deinit();
    // Skip argv[0] (executable path) — the iterator starts at it.
    _ = it.next();

    var opts = Options{};

    while (it.next()) |item| {
        if (std.mem.eql(u8, item, "--")) break;
        if (std.mem.startsWith(u8, item, "--")) {
            try parseLong(&opts, item[2..], &it, arena);
        } else if (item.len > 1 and item[0] == '-') {
            try parseShort(&opts, item[1..], &it, arena);
        } else {
            scoped.err("Unknown option: {s}\n", .{item});
            return error.failed_args_parsing;
        }
    }
    return opts;
}

fn parseLong(opts: *Options, body: []const u8, it: *std.process.Args.Iterator, arena: std.mem.Allocator) !void {
    const name, const inline_val = splitEq(body);
    const field_names = @typeInfo(Options).@"struct".field_names;
    inline for (field_names) |fname| {
        if (std.mem.eql(u8, name, fname)) {
            try assignField(opts, fname, inline_val, it, arena);
            return;
        }
    }
    scoped.err("Unknown option: --{s}\n", .{name});
    return error.failed_args_parsing;
}
fn parseShort(opts: *Options, cluster: []const u8, it: *std.process.Args.Iterator, arena: std.mem.Allocator) !void {
    const sh_names = @typeInfo(@TypeOf(Options.shorthands)).@"struct".field_names;
    inline for (sh_names) |sname| {
        for (cluster, 0..) |ch, idx| {
            if (ch != sname[0]) continue;
            const long_name = @field(Options.shorthands, sname);
            const Field = @TypeOf(@field(opts, long_name));
            if (Field == bool) {
                @field(opts, long_name) = true;
                continue;
            }
            if (idx != cluster.len - 1) {
                scoped.err("Option -{c} requires a value and must be last in a cluster\n", .{ch});
                return error.failed_args_parsing;
            }
            const next = it.next() orelse {
                scoped.err("Option -{c} requires a value\n", .{ch});
                return error.failed_args_parsing;
            };
            try assignField(opts, long_name, next, it, arena);
            return;
        }
        return;
    }
    scoped.err("Unknown shorthand cluster: -{s}\n", .{cluster});
    return error.failed_args_parsing;
}

fn splitEq(s: []const u8) struct { []const u8, ?[]const u8 } {
    if (std.mem.indexOfScalar(u8, s, '=')) |i| return .{ s[0..i], s[i + 1 ..] };
    return .{ s, null };
}


fn assignField(opts: *Options, comptime name: []const u8, value: ?[]const u8, it: *std.process.Args.Iterator, arena: std.mem.Allocator) !void {
    const Field = @TypeOf(@field(opts, name));
    if (Field == bool) {
        @field(opts, name) = true;
        return;
    }
    const raw = value orelse it.next() orelse {
        scoped.err("Option --{s} requires a value\n", .{name});
        return error.failed_args_parsing;
    };
    @field(opts, name) = try arena.dupeSentinel(u8, raw, 0);
}

pub fn main(init: std.process.Init) !u8 {
    const op = parseOptions(init) catch return 2;
    var app = BottomConsoleApp.init(init.io, op);
    app.run();
    return app.deinit();
}