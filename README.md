# Bottom-Zig

This in an implementaion of the Bottom Spec in Zig.
This is a complete implementation of the Bottom Spec, thus all changes are related to fitting better to the Spec, the implementation breaking on a new zig version, or added tests or bugs fixes.
# Features

- Encodes the bottom format
- Decodes the bottom format
- Has a CLI (Basically bottom-rs implementation options)
- You can use it in your projects

# Upcomming Developments

- My doc comments and comments
- Errors are a bit not user friendly

# How to build

To build you need to clone with `git clone https://github.com/Deecellar/bottom-zig --recurse` to get all the source files and dependencies
after the fact you can use `zig build` and it should work.

Note that you can use to tune performance -Drelease-safe (To get errors with more detail) -Drelease-fast (Fast performance) and -Drelease-small (Small binary)
You can also use it as a lib using zig referencing bottom.zig in your code =) 

# Releases
I will not do semver to do a release per se not a specifc thing here, so here you go, the closest to that is this =P
https://deecellar.github.io/bottom-zig/ - Wasm usage on bottom-zig
If you want a native binary, in the CI, the lastest job called "CI" will have artifacts for linux, mac and windows (x86_64)
# Thanks to

- Andrew for making an awesome language
- MasterQ32 for making zig args and being awesome
- der-teufel-programming for saying I should do this
- =3

# License

All this project is MIT baby.
