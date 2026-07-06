//! # Bottom Encoding/Decoding Lookup Tables
//!
//! Provides compile-time generated lookup tables for Bottom emoji encoding:
//! - BottomLut: Encodes bytes 0-255 to Bottom emoji sequences
//! - BottomDecodeLut: Decodes Bottom sequences back to bytes using hash table
//!
//! The Bottom encoding represents bytes as combinations of emoji:
//! 🫂=200, 💖=50, ✨=10, 🥺=5, ,,,,=4, ,,,=3, ,,=2, ,=1, ❤=0
//! Each sequence ends with delimiter 👉👈

const std = @import("std");

pub const BottomLut = struct {
    const buffers = generateLut()[0];
    const lengths = generateLut()[1];

    pub inline fn lut(b: u8) []const u8 {
        return buffers[b][0..lengths[b]];
    }

    /// Generate encoding lookup table at compile time.
    /// Uses greedy algorithm to represent each byte as emoji combination.
    pub fn generateLut() struct { [256][40]u8, [256]usize } {
        @setEvalBranchQuota(100_000_000);
        var bufs: [256][40]u8 = undefined;
        var lens: [256]usize = undefined;

        const tokens = .{
            .{ "🫂", 200 }, .{ "💖", 50 }, .{ "✨", 10 }, .{ "🥺", 5 },
            .{ ",,,,", 4 },   .{ ",,,", 3 },   .{ ",,", 2 },   .{ ",", 1 },
        };

        for (0..256) |i| {
            var out = bufs[i][0..];
            var idx: usize = 0;
            var b: u8 = @intCast(i);

            if (b == 0) {
                const z = "❤";
                @memcpy(out[idx .. idx + z.len], z);
                idx += z.len;
            }
            while (b != 0) {
                inline for (tokens) |tok| {
                    if (b >= tok[1]) {
                        b -= tok[1];
                        const s: []const u8 = tok[0];
                        @memcpy(out[idx .. idx + s.len], s);
                        idx += s.len;
                        break;
                    }
                }
            }
            const end = "👉👈";
            @memcpy(out[idx .. idx + end.len], end);
            idx += end.len;

            if (idx < out.len) @memset(out[idx..], 0);
            lens[i] = idx;
        }
        return .{ bufs, lens };
    }
};

pub const BottomDecodeLut = struct {
    pub const delimiter = "👉👈";

    const Entry = struct { key: u64, value: u8 };
    // 512-entry hash table for 256 codes. Load factor ~0.5 for fast lookups.
    const table_size = 512;
    const mask = table_size - 1;
    const table = buildTable();

    /// Decode a Bottom sequence (without delimiter) to its original byte.
    /// Returns null if sequence is invalid or not in the encoding table.
    /// Uses XxHash64 + open addressing for O(1) expected lookup time.
    pub inline fn decode(sequence: []const u8) ?u8 {
        @setRuntimeSafety(false);
        // Reject sequences that exceed maximum encoded length.
        if (sequence.len + delimiter.len > 40) return null;

        // Hash the sequence + delimiter to match encoding format.
        var hasher = std.hash.XxHash64.init(0);
        hasher.update(sequence);
        hasher.update(delimiter);
        const key = hasher.final();

        // Linear probing until match or empty slot.
        var i: usize = @intCast(key & mask);
        while (true) : (i = (i + 1) & mask) {
            const e = table[i];
            if (e.key == 0) return null;
            if (e.key == key) return e.value;
        }
    }

    /// Build the decode hash table at compile time.
    /// Inserts all 256 encoded sequences with linear probing collision resolution.
    fn buildTable() [table_size]Entry {
        @setEvalBranchQuota(100_000_000);
        var t: [table_size]Entry = @splat(.{ .key = 0, .value = 0 });

        inline for (0..256) |i| {
            const enc = BottomLut.lut(@intCast(i));
            var hasher = std.hash.XxHash64.init(0);
            hasher.update(enc);
            const key = hasher.final();

            // Linear probe to find empty slot. Guaranteed to succeed with LF=0.5.
            var idx: usize = @intCast(key & mask);
            while (true) : (idx = (idx + 1) & mask) {
                if (t[idx].key == 0) {
                    t[idx] = .{ .key = key, .value = @intCast(i) };
                    break;
                }
            }
        }

        // Compile-time validation: ensure all 256 codes were inserted.
        var count: usize = 0;
        for (t) |e| {
            if (e.key != 0) count += 1;
        }
        if (count != 256) {
            @compileError(std.fmt.comptimePrint("Hash table build failed: {d}/256 entries", .{count}));
        }
        return t;
    }
};

// The DFA is a packed 2D state-transition table that fits in exactly 8 KB
// (16 states × 256 byte values × 2 bytes per entry). It walks encoded Bottom
// data one byte at a time, accumulating a running sum and emitting a decoded
// byte whenever the 👉👈 delimiter's final byte is observed.
//
// The "comma cheat" — since the DFA loops on every `,` byte and adds 1 to
// the running sum, we only need to teach the DFA a single `,` token. Sequences
// like `,,` and `,,,` naturally decode to 2 and 3 without explicit entries.
//
// The table is generated at compile time from the Bottom emoji alphabet,
// sharing UTF-8 prefix paths between tokens (e.g. 🫂, 💖, 🥺, 👉 all begin
// with `f0 9f`, so their first two transitions share sub-states).

pub const DfaAction = packed struct(u16) {
    next: u6,        // Next state (supports up to 64 states)
    is_end: u1,      // True for the final byte of the 👉👈 delimiter
    is_invalid: u1,  // True if the byte does not continue any path
    add: u8,         // Value to add to the running sum
};

pub const DfaTable = [16][256]DfaAction;

/// Compile-time generated DFA for decoding the Bottom emoji alphabet.
/// Total footprint: 16 × 256 × 2 bytes = 8 KiB — fits inside the L1 cache
/// of any modern CPU, removing all D-cache misses from the hot path.
pub const BOTTOM_DFA: DfaTable = generateBottomDfa();

/// Walk every token through the 2D table at compile time, creating new
/// sub-states for prefix bytes that are not yet present. All entries default
/// to `.is_invalid = 1` so that any byte we don't recognize resets the
/// stream.
fn generateBottomDfa() DfaTable {
    @setEvalBranchQuota(100_000);

    var table: DfaTable = undefined;

    // 1. Initialize the entire table as invalid.
    for (&table) |*row| {
        for (row) |*action| {
            action.* = .{
                .next = 0,
                .is_end = 0,
                .is_invalid = 1,
                .add = 0,
            };
        }
    }

    var next_available_state: u6 = 1;

    const wire = struct {
        fn wire(
            comptime bytes: []const u8,
            value: u8,
            comptime final_is_end: bool,
            t: *DfaTable,
            next_state: *u6,
        ) void {
            var curr: u6 = 0;
            for (bytes, 0..) |byte, i| {
                const is_last = (i == bytes.len - 1);
                if (is_last) {
                    t[curr][byte] = .{
                        .next = 0,
                        .is_end = if (final_is_end) 1 else 0,
                        .is_invalid = 0,
                        .add = value,
                    };
                } else {
                    if (t[curr][byte].is_invalid == 1) {
                        t[curr][byte] = .{
                            .next = next_state.*,
                            .is_end = 0,
                            .is_invalid = 0,
                            .add = 0,
                        };
                        next_state.* += 1;
                    }
                    curr = t[curr][byte].next;
                }
            }
        }
    }.wire;

    const Token = struct { str: []const u8, val: u8 };
    const tokens = [_]Token{
        .{ .str = "🫂", .val = 200 },
        .{ .str = "💖", .val = 50 },
        .{ .str = "✨", .val = 10 },
        .{ .str = "🥺", .val = 5 },
        .{ .str = ",",  .val = 1 },
        .{ .str = "❤",  .val = 0 },
    };
    for (tokens) |tok| {
        wire(tok.str, tok.val, false, &table, &next_available_state);
    }

    wire("👉👈", 0, true, &table, &next_available_state);

    return table;
}

test "DFA round-trips every byte 0..255" {
    for (0..256) |i| {
        const byte: u8 = @intCast(i);
        const encoded = BottomLut.lut(byte);

        var state: u6 = 0;
        var running_sum: u8 = 0;
        var decoded: ?u8 = null;

        for (encoded) |b| {
            const action = BOTTOM_DFA[state][b];
            if (action.is_invalid == 1) {
                state = 0;
                running_sum = 0;
                continue;
            }
            running_sum +%= action.add;
            state = action.next;
            if (action.is_end == 1) {
                decoded = running_sum;
                running_sum = 0;
            }
        }

        try std.testing.expect(decoded != null);
        try std.testing.expectEqual(byte, decoded.?);
    }
}

test "DFA emits correct sums for repeated commas" {
    var state: u6 = 0;
    var running_sum: u8 = 0;

    const delimiter = "👉👈";
    const input = ",,,,," ++ delimiter; // 5 commas → running_sum = 5

    var emitted: ?u8 = null;
    for (input) |b| {
        const action = BOTTOM_DFA[state][b];
        if (action.is_invalid == 1) {
            state = 0;
            running_sum = 0;
            continue;
        }
        running_sum +%= action.add;
        state = action.next;
        if (action.is_end == 1) {
            emitted = running_sum;
            running_sum = 0;
        }
    }

    try std.testing.expectEqual(@as(?u8, 5), emitted);
}

test "DFA rejects invalid bytes and recovers" {
    var state: u6 = 0;
    var running_sum: u8 = 0;

    const valid = "💖🥺,👉👈"; // 50 + 5 + 1 = 56 = '8'
    const garbage = "ZZ";      // not in alphabet; should reset the DFA
    const input = garbage ++ valid;

    var emitted: ?u8 = null;
    for (input) |b| {
        const action = BOTTOM_DFA[state][b];
        if (action.is_invalid == 1) {
            state = 0;
            running_sum = 0;
            continue;
        }
        running_sum +%= action.add;
        state = action.next;
        if (action.is_end == 1) {
            emitted = running_sum;
            running_sum = 0;
        }
    }

    try std.testing.expectEqual(@as(?u8, '8'), emitted);
}

test "encode and decode round trip" {
    for (0..256) |i| {
        const byte: u8 = @intCast(i);
        const encoded = BottomLut.lut(byte);

        const delimiter = "👉👈";
        const sequence = if (std.mem.endsWith(u8, encoded, delimiter))
            encoded[0 .. encoded.len - delimiter.len]
        else
            encoded;

        const decoded = BottomDecodeLut.decode(sequence);
        try std.testing.expect(decoded != null);
        try std.testing.expectEqual(byte, decoded.?);
    }
}

test "decode invalid sequences" {
    try std.testing.expectEqual(@as(?u8, null), BottomDecodeLut.decode("invalid"));
    try std.testing.expectEqual(@as(?u8, null), BottomDecodeLut.decode(""));

    const too_long = "💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖";
    try std.testing.expectEqual(@as(?u8, null), BottomDecodeLut.decode(too_long));
}

/// SIMD-accelerated substring search.
/// Based on: https://aarol.dev/posts/zig-simd-substr/
/// Uses two-character heuristic to filter candidates before full comparison.
pub fn indexOf(haystack: []const u8, needle: []const u8) ?usize {
    const n = haystack.len;
    const k = needle.len;
    if (k == 0 or k > n) return null;
    const maybe_len = std.simd.suggestVectorLength(u8);
    const block_size = maybe_len.?;
    const Block = @Vector(block_size, u8);

    const first_offset, const second_offset =
        findRarest(needle) orelse [2]usize{ 0, @intCast(k - 1) };

    const first_letter: Block = @splat(needle[first_offset]);
    const second_letter: Block = @splat(needle[second_offset]);
    const max_off = if (first_offset > second_offset) first_offset else second_offset;

    var i: usize = 0;
    while (i + max_off + block_size <= n) : (i += block_size) {
        const first_block: Block = haystack[i + first_offset ..][0..block_size].*;
        const second_block: Block = haystack[i + second_offset ..][0..block_size].*;
        const eq_first = first_letter == first_block;
        const eq_second = second_letter == second_block;
        const mask_val = eq_first & eq_second;

        if(@reduce(.Or, mask_val) == false) continue;
        var mask: std.bit_set.IntegerBitSet(block_size) = .{ .mask = @bitCast(mask_val) };
        while (mask.findFirstSet()) |bitpos| {
            if (std.mem.eql(u8, haystack[i + bitpos ..][0..k], needle)) {
                return i + bitpos;
            }
            _ = mask.toggleFirstSet();
        }
    }
    // Scalar fallback for remaining bytes that don't fill a SIMD block
    if (i < n) {
        if (std.mem.indexOf(u8, haystack[i..], needle)) |rel_idx| {
            return i + rel_idx;
        }
    }
    return null;
}

/// Find two rarest characters in needle for SIMD search heuristic.
/// Returns indices of two least-common bytes based on RANK frequency table.
fn findRarest(needle: []const u8) ?[2]usize {
    if (needle.len <= 1 or needle.len > 256) {
        return null;
    }

    var rare1: u8 = needle[0];
    var index1: usize = 0;
    var rare2: u8 = needle[1];
    var index2: usize = 1;
    if (RANK[rare2] < RANK[rare1]) {
        std.mem.swap(u8, &rare1, &rare2);
        std.mem.swap(usize, &index1, &index2);
    }
    for (needle[2..], 2..) |b, i| {
        if (RANK[b] < RANK[rare1]) {
            rare2 = rare1;
            index2 = index1;
            rare1 = b;
            index1 = @intCast(i);
        } else if (b != rare1 and RANK[b] < RANK[rare2]) {
            rare2 = b;
            index2 = @intCast(i);
        }
    }

    std.debug.assert(index1 != index2);
    return [2]usize{ index1, index2 };
}

// Byte frequency ranking for English text (lower = rarer).
// Source: BurntSushi's memchr
// https://github.com/BurntSushi/memchr/blob/master/src/arch/all/packedpair/default_rank.rs
const RANK = [256]u8{
    55, // '\x00'
    52, // '\x01'
    51, // '\x02'
    50, // '\x03'
    49, // '\x04'
    48, // '\x05'
    47, // '\x06'
    46, // '\x07'
    45, // '\x08'
    103, // '\t'
    242, // '\n'
    66, // '\x0b'
    67, // '\x0c'
    229, // '\r'
    44, // '\x0e'
    43, // '\x0f'
    42, // '\x10'
    41, // '\x11'
    40, // '\x12'
    39, // '\x13'
    38, // '\x14'
    37, // '\x15'
    36, // '\x16'
    35, // '\x17'
    34, // '\x18'
    33, // '\x19'
    56, // '\x1a'
    32, // '\x1b'
    31, // '\x1c'
    30, // '\x1d'
    29, // '\x1e'
    28, // '\x1f'
    255, // ' '
    148, // '!'
    164, // '"'
    149, // '#'
    136, // '$'
    160, // '%'
    155, // '&'
    173, // "'"
    221, // '('
    222, // ')'
    134, // '*'
    122, // '+'
    232, // ','
    202, // '-'
    215, // '.'
    224, // '/'
    208, // '0'
    220, // '1'
    204, // '2'
    187, // '3'
    183, // '4'
    179, // '5'
    177, // '6'
    168, // '7'
    178, // '8'
    200, // '9'
    226, // ':'
    195, // ';'
    154, // '<'
    184, // '='
    174, // '>'
    126, // '?'
    120, // '@'
    191, // 'A'
    157, // 'B'
    194, // 'C'
    170, // 'D'
    189, // 'E'
    162, // 'F'
    161, // 'G'
    150, // 'H'
    193, // 'I'
    142, // 'J'
    137, // 'K'
    171, // 'L'
    176, // 'M'
    185, // 'N'
    167, // 'O'
    186, // 'P'
    112, // 'Q'
    175, // 'R'
    192, // 'S'
    188, // 'T'
    156, // 'U'
    140, // 'V'
    143, // 'W'
    123, // 'X'
    133, // 'Y'
    128, // 'Z'
    147, // '['
    138, // '\\'
    146, // ']'
    114, // '^'
    223, // '_'
    151, // '`'
    249, // 'a'
    216, // 'b'
    238, // 'c'
    236, // 'd'
    253, // 'e'
    227, // 'f'
    218, // 'g'
    230, // 'h'
    247, // 'i'
    135, // 'j'
    180, // 'k'
    241, // 'l'
    233, // 'm'
    246, // 'n'
    244, // 'o'
    231, // 'p'
    139, // 'q'
    245, // 'r'
    243, // 's'
    251, // 't'
    235, // 'u'
    201, // 'v'
    196, // 'w'
    240, // 'x'
    214, // 'y'
    152, // 'z'
    182, // '{'
    205, // '|'
    181, // '}'
    127, // '~'
    27, // '\x7f'
    212, // '\x80'
    211, // '\x81'
    210, // '\x82'
    213, // '\x83'
    228, // '\x84'
    197, // '\x85'
    169, // '\x86'
    159, // '\x87'
    131, // '\x88'
    172, // '\x89'
    105, // '\x8a'
    80, // '\x8b'
    98, // '\x8c'
    96, // '\x8d'
    97, // '\x8e'
    81, // '\x8f'
    207, // '\x90'
    145, // '\x91'
    116, // '\x92'
    115, // '\x93'
    144, // '\x94'
    130, // '\x95'
    153, // '\x96'
    121, // '\x97'
    107, // '\x98'
    132, // '\x99'
    109, // '\x9a'
    110, // '\x9b'
    124, // '\x9c'
    111, // '\x9d'
    82, // '\x9e'
    108, // '\x9f'
    118, // '\xa0'
    141, // '¡'
    113, // '¢'
    129, // '£'
    119, // '¤'
    125, // '¥'
    165, // '¦'
    117, // '§'
    92, // '¨'
    106, // '©'
    83, // 'ª'
    72, // '«'
    99, // '¬'
    93, // '\xad'
    65, // '®'
    79, // '¯'
    166, // '°'
    237, // '±'
    163, // '²'
    199, // '³'
    190, // '´'
    225, // 'µ'
    209, // '¶'
    203, // '·'
    198, // '¸'
    217, // '¹'
    219, // 'º'
    206, // '»'
    234, // '¼'
    248, // '½'
    158, // '¾'
    239, // '¿'
    255, // 'À'
    255, // 'Á'
    255, // 'Â'
    255, // 'Ã'
    255, // 'Ä'
    255, // 'Å'
    255, // 'Æ'
    255, // 'Ç'
    255, // 'È'
    255, // 'É'
    255, // 'Ê'
    255, // 'Ë'
    255, // 'Ì'
    255, // 'Í'
    255, // 'Î'
    255, // 'Ï'
    255, // 'Ð'
    255, // 'Ñ'
    255, // 'Ò'
    255, // 'Ó'
    255, // 'Ô'
    255, // 'Õ'
    255, // 'Ö'
    255, // '×'
    255, // 'Ø'
    255, // 'Ù'
    255, // 'Ú'
    255, // 'Û'
    255, // 'Ü'
    255, // 'Ý'
    255, // 'Þ'
    255, // 'ß'
    255, // 'à'
    255, // 'á'
    255, // 'â'
    255, // 'ã'
    255, // 'ä'
    255, // 'å'
    255, // 'æ'
    255, // 'ç'
    255, // 'è'
    255, // 'é'
    255, // 'ê'
    255, // 'ë'
    255, // 'ì'
    255, // 'í'
    255, // 'î'
    255, // 'ï'
    255, // 'ð'
    255, // 'ñ'
    255, // 'ò'
    255, // 'ó'
    255, // 'ô'
    255, // 'õ'
    255, // 'ö'
    255, // '÷'
    255, // 'ø'
    255, // 'ù'
    255, // 'ú'
    255, // 'û'
    255, // 'ü'
    255, // 'ý'
    255, // 'þ'
    255, // 'ÿ'
};
