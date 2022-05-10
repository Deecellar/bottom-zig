const std = @import("std");
const bottom = @import("bottom");
const args = @import("zig-args");
const build_options = @import("build_options");
const help_text = @embedFile("help.txt");
const bufferSize = 128 * 1024;

/// We create options similar to bottom RS
const Options = struct {
    bottomiffy: ?bool = null,
    help: bool = false,
    regress: ?bool = null,
    version: bool = false,
    input: ?[]const u8 = null,
    output: ?[]const u8 = null,
    pub const shorthands = .{
        .b = "bottomiffy",
        .h = "help",
        .r = "regress",
        .V = "version",
        .i = "input",
        .o = "output",
    };
};
pub fn main() void {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            std.log.err("Your windows console does not support UTF-8, try using Windows Terminal {s}", .{"https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701?hl=en-us&gl=US"});
            std.os.exit(5);
        }
    }
    consoleApp() catch {};
}
pub fn consoleApp() !void {
    var allocator: std.mem.Allocator = undefined;
    var arena: std.heap.ArenaAllocator = undefined;
    defer arena.deinit();
    if (build_options.use_c) {
        arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    } else {
        var generalPurpose = std.heap.GeneralPurposeAllocator(.{}){};
        arena = std.heap.ArenaAllocator.init(generalPurpose.allocator());
    }
    allocator = arena.allocator();
    errdefer arena.deinit();
    const options = args.parseForCurrentProcess(Options, allocator, .print) catch return std.os.exit(1);
    defer options.deinit();
    var stderr = std.io.getStdErr();
    defer stderr.close();
    errdefer stderr.close();
    if (options.options.help) {
        try help();
        std.os.exit(0);
    }
    if (options.options.version) {
        try version();
        std.os.exit(0);
    }
    if (options.options.bottomiffy == null and options.options.regress == null) {
        try help();
        try stderr.writer().writeAll("You have to specify either bottomify or regress OwO");
        std.os.exit(1);
    }
    var bottomiffy_option: bool = options.options.bottomiffy orelse false;
    var regress_option: bool = options.options.regress orelse false;
    if (bottomiffy_option and regress_option) {
        try help();
        try stderr.writer().writeAll("You cannot use both bottomify and regress UwU");
        std.os.exit(1);
    }

    var inputFile = std.io.getStdIn();
    errdefer inputFile.close();
    defer inputFile.close();

    var outputFile = std.io.getStdOut();
    errdefer outputFile.close();
    defer outputFile.close();
    if (options.options.input) |path| {
        inputFile = std.fs.cwd().openFile(path, std.fs.File.OpenFlags{}) catch std.os.exit(2);
    }
    if (options.options.output) |path| {
        outputFile = std.fs.cwd().createFile(path, std.fs.File.CreateFlags{}) catch std.os.exit(2);
    }
    if (bottomiffy_option) {
        try bottomiffy(inputFile, outputFile);
    }
    if (regress_option) {
        try regress(inputFile, outputFile);
    }
    std.os.exit(0);
}
pub fn bottomiffy(fileInput: std.fs.File, fileOutput: std.fs.File) !void {
    var bufferInput: std.io.BufferedReader(bufferSize, std.fs.File.Reader) = .{ .unbuffered_reader = fileInput.reader() };
    var bufferOut: std.io.BufferedWriter(bufferSize * bottom.encoder.max_expansion_per_byte, std.fs.File.Writer) = .{ .unbuffered_writer = fileOutput.writer() };
    var bufferBottom: [bufferSize * bottom.encoder.max_expansion_per_byte]u8 = undefined;
    var buffer: [bufferSize]u8 = undefined;
    var size: usize = 1;
    defer bufferOut.flush() catch |err| {
        std.log.err("Error while flushing output: {}", .{err});
        std.os.exit(3);
    };
    if (fileInput.handle == std.io.getStdIn().handle) {
        var stdin_buffer = bufferInput.reader().readUntilDelimiter(&buffer, '\n') catch |err| {
            std.log.err("Error while reading input from stdin: {}, the max buffer size on console is {d}", .{ err, bufferSize });
            std.os.exit(1);
        };
        var outbuffer: []u8 = bottom.encoder.encode(stdin_buffer, &bufferBottom);
        _ = try bufferOut.writer().writeAll(outbuffer);
        if(fileOutput.handle == std.io.getStdOut().handle) {
            _ = try bufferOut.writer().write("\n");
        }
        buffer = undefined;
        bufferBottom = undefined;
        return;
    }
    while (size != 0) {
        size = try bufferInput.read(&buffer);
        if (size > 0) {
            var outbuffer: []u8 = bottom.encoder.encode(buffer[0 .. size - 1], &bufferBottom);
            _ = try bufferOut.writer().writeAll(outbuffer);
            buffer = undefined;
            bufferBottom = undefined;
        }
    }
}
pub fn regress(fileInput: std.fs.File, fileOutput: std.fs.File) !void {
    var bufferInput: std.io.BufferedReader(bufferSize, std.fs.File.Reader) = .{ .unbuffered_reader = fileInput.reader() };
    var bufferOut: std.io.BufferedWriter(bufferSize * bottom.encoder.max_expansion_per_byte, std.fs.File.Writer) = .{ .unbuffered_writer = fileOutput.writer() };
    var bufferRegress: [bufferSize * bottom.encoder.max_expansion_per_byte]u8 = undefined;
    var buffer: [bufferSize]u8 = undefined;
    var temp: []u8 = &@as([1]u8, undefined);
    while (temp.len != 0) {
        temp = (try bufferInput.reader().readUntilDelimiterOrEof(&buffer, "👈"[3])) orelse &@as([0]u8, undefined);
        if (temp.len > 0) {
            var outbuffer: u8 = bottom.decoder.decodeByte(temp[0 .. temp.len - 7]);
            _ = try bufferOut.writer().writeByte(outbuffer);
            buffer = undefined;
            bufferRegress = undefined;
        }
    }
    try bufferOut.flush();
}
pub fn help() !void {
    try std.io.getStdOut().writer().writeAll(help_text);
}

pub fn version() !void {
    try std.io.getStdOut().writer().writeAll(build_options.version);
}
