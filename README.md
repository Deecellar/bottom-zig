# Bottom-Zig

This in an implementaion of the Bottom Spec in Zig, now, this really a bad implementation, it decodes and encodes fine enough, decodes fine enough, but decoding is slow as fuck just because I did not wanna use a hashmap =)
on the other hand, I did not use much of error control nor fine user interface, this will crash on you and it will be the same as it would've succeded
Why I am publishing something incomplete, since I don't care =3

# Features

- Encodes the bottom format
- Decodes the bottom format
- Has a CLI (Basically bottom-rs implementation options)
- You can use it in your projects

# Things that does not work

- My doc comments and comments

# Will I continue

Probably (And I did)

# How to build

To build you need to clone with `git clone https://github.com/Deecellar/bottom-zig --recurse` to get all the source files and dependencies
after the fact you can use `zig build` and it should work.

Note that you can use to tune performance -Drelease-safe (To get errors with more detail) -Drelease-fast (Fast performance) and -Drelease-small (Small binary)
You can also use it as a lib referencing bottom.zig in your code =)

# Thanks to

- Andrew for making an awesome language
- MasterQ32 for making zig args and being awesome
- der-teufel-programming for saying I should do this
- #offtopic for being a funny place
- Dunno?
- My Top?
- My Bottom?
- I am just writing stuff here now
- =3

# License

All this project is MIT baby.
