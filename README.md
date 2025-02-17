# Bottom-Zig

A complete implementation of the Bottom Spec in Zig with both encoding and decoding capabilities.

# Features

- Bottom format encoding/decoding
- CLI interface compatible with bottom-rs options
- Static and shared library support
- WebAssembly build target
- C API bindings
- Configurable allocators when targeting zig

# Upcoming Features

- Speed improvements

# Build Options

```bash
# Basic build
zig build

# Run tests
zig build test-exe    # CLI tests
zig build test-lib    # Library tests

# Install library only
zig build install-lib

# Build WebAssembly
zig build wasm-shared

# Build benchmarks
zig build benchmark
# Run benchmarks
zig build run-benchmark


```

# Usage

As a dependency in your `build.zig.zon` via zig fetch. use the standard way of adding a module to your project.

# Bottom CLI Usage

```bash
# Encode
bottom-zig
--bottomify "Hello World"     # 🫂💖✨✨,,👉👈💖✨✨🫂👉👈💖✨✨,👉👈💖✨,,👉👈💖✨✨✨,👉👈💖✨✨✨,,👉👈💖✨,,👉👈💖✨✨✨,👉👈💖✨✨✨,,👉👈✨✨,👉👈💖✨✨✨👉👈💖✨✨✨,👉👈💖✨✨✨,,👉👈💖✨,,👉👈💖✨✨✨👉👈

# Decode
bottom-zig --regress "🫂💖✨✨,,👉👈💖✨✨🫂👉👈💖✨✨,👉👈💖✨,,👉👈💖✨✨✨,👉👈💖✨✨✨,,👉👈💖✨,,👉👈💖✨✨✨,👉👈💖✨✨✨,,👉👈✨✨,👉👈💖✨✨✨👉👈💖✨✨✨,👉👈💖✨✨✨,,👉👈💖✨,,👉👈💖✨✨✨👉👈"    # Hello World

# Use with files
bottom-zig --bottomify -i input.txt -o output.txt
bottom-zig --regress -i output.txt
```

# C API Usage

See `include/bottom.h` for the API definition.

For an example of how to use the C API, see `src/example.c`.


# Online Demo
Try it in WebAssembly: https://deecellar.github.io/bottom-zig/

# Binaries
Pre-built binaries for Linux, macOS and Windows (x86_64) are available in CI artifacts.

# License
MIT License

# Thanks to
- Andrew for making an awesome language
- MasterQ32 for making zig args and being awesome
- der-teufel-programming for saying I should do this
- =3
