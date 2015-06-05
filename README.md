# `std-with-cargo`

Cross compile the `std` crate using `cargo`.

## What is this?

A collection of patches for the rust-lang/rust repo that will make the `std` crate cross compilable
with `cargo`.

## Why use `cargo` to cross compile the `std` crate?

Two reasons:

### Easier cross compilation

One of the usual (1) [requirements] for cross compiling a Rust program is a cross compiled `std`
crate. Right now, the only (?) way to get that is to build it yourself using the Rust build system
(`configure --target=$TRIPLE && make`) but this is time consuming and wasteful -- the build
system will bootstrap a native Rust toolchain (this takes 30+ mins) and then use that toolchain to
cross compile the `std` crate and co.

[requirements]: https://github.com/japaric/rust-on-openwrt#cross-compilation-requirements

A much faster way is to use the Rust toolchain that you already have installed, instead of
bootstrapping a new one, along with `cargo`, this can bring down the build time to less than one
minute (with full optimizations enabled).

(1) Unless you are targeting a bare metal (no OS) device, in that case you probably only want a
cross compiled `core` crate, but theses patches can also help with that use case.

### Making Rust binaries smaller

Rust binaries are *huge*, the size of "hello world" cross compiled for MIPS (with
`-C lto -O -C link-args=-s`) is 309KB. If you are targeting a router with only 8MB of flash, where
half of that has already been taken by the OS, those sizes are discouraging.

`-C prefer-dynamic` doesn't really help, that may make the binary smaller than 10KB, but then you
would need to install `libstd.so`, which is ~4.8MB (!), in the target device, so you end up
requiring way more memory than in the statically linked case.

But, why are Rust binaries so large? If you inspect them using `nm --size-sort -S`, you'll find out
that a good chunk of the binary is jemalloc, and `RUST_BACKTRACE` support. To quantify how much is
a "good chunk", I tested disabling jemalloc, that brought the size of "hello world" down to 146K,
and then with a small modification to the `std` crate I also disabled backtrace support, and the
size of "hello world" went down to 73K, that's a ~75% reduction in size.

How does `cargo` fit in all this? The changes I mentioned above were implemented using `cargo`
features, and both jemalloc and backtrace support are now optional features. This means that you
could, for example, enable backtrace support during development phase, and disable it for release
to get smaller binaries; or pick between malloc (smaller footprint) and jemalloc (better
performance) as the allocator for your program.

---

Another interesting idea to explore is dynamically linking to `libjemalloc` and `libbacktrace`,
rather than statically, like all Rust programs do today. This would reduce each binary by 200KB+,
while keeping both jemalloc and backtrace support enabled, at the cost of having to install
`libjemalloc.so` and `libbacktrace.so` in the target device. This option is not provided by the
Rust build system, but seems doable with `cargo`.

## Dependencies

To cross compile the `std` crate you'll need:

- Rust nightly channel
- The usual stuff for cross compilation: toolchain and cross compiled C libraries
- LLVM, in particular `llvm-mc` should be in your PATH

## How to use

If you have a rust repo lying around, you could simply apply the patches provided by this
repository, but be sure to first checkout the repo to match the version of your installed `rustc`.

```
$ cd /path/to/rust

$ rustc -Vv
rustc 1.2.0-nightly (613e57b44 2015-06-01) (built 2015-06-02)
binary: rustc
commit-hash: 613e57b448c88591b6076a8cea9799f1f3876687
commit-date: 2015-06-01
build-date: 2015-06-02
host: x86_64-unknown-linux-gnu
release: 1.2.0-nightly

$ git checkout 613e57b448c88591b6076a8cea9799f1f3876687

$ patch -p1 < /path/to/some.patch
```

Otherwise, you can use the `fetch-and-patch-rust.sh` script, it will download a snapshot of
rust-lang/rust that matches your installed `rustc` and apply the patches.

Once you have a patched rust repo, modify the Cargo.toml of the program that will be cross compiled
to depend on the patched `std` crate:

```
# hello world example
$ cargo new --bin hello

$ cd hello

$ cat Cargo.toml
(..)
[dependencies.std]
path = /path/to/patched/rust/src/lisbtd
# optionally enable jemalloc and backtrace support
features = ["jemalloc", "backtrace"]

# don't forget to enable LTO for smaller binaries
[profile.release]
lto = true
```

Additionally, you'll need to set these two environment variables to tell `cargo` which compiler and
archiver to use:

```
export AR_mips_unknown_linux_gnu=mips-openwrt-linux-ar
export CC_mips_unknown_linux_gnu=mips-openwrt-linux-gcc
```

Note to the each variable is suffixed by the target triple, in this case I'm targeting a
`mips-unknown-linux-gnu` device.

With all that set, you can call `cargo build --target=$TRIPLE` like you normally would:

```
$ cargo build --target=mips-unknown-linux-gnu --release
   Compiling core v0.0.0 (file:///home/japaric/tmp/rust/src/hello)
   Compiling rustc_bitflags v0.0.0 (file:///home/japaric/tmp/rust/src/hello)
   Compiling gcc v0.3.6
   Compiling std v0.0.0 (file:///home/japaric/tmp/rust/src/hello)
   Compiling libc v0.0.0 (file:///home/japaric/tmp/rust/src/hello)
   Compiling rustc_unicode v0.0.0 (file:///home/japaric/tmp/rust/src/hello)
   Compiling rand v0.0.0 (file:///home/japaric/tmp/rust/src/hello)
   Compiling alloc v0.0.0 (file:///home/japaric/tmp/rust/src/hello)
   Compiling collections v0.0.0 (file:///home/japaric/tmp/rust/src/hello)
   Compiling hello v0.1.0 (file:///home/japaric/tmp/rust/src/hello)

$ file target/mips-unknown-linux-gnu/release/hello
target/mips-unknown-linux-gnu/release/hello: ELF 32-bit MSB shared object, MIPS, MIPS32 rel2 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, not stripped
```

## What do the patches do?

The `cargo-ify.patch` adds a bunch of `Cargo.toml`s with information about the dependencies between
crates. It also adds `build.rs`s to handle cross compilation of C dependencies like jemalloc,
backtrace, compiler-rt, etc.

The `remove-mno-compact-eh-flag.patch` only matters if you are targeting the
`mips-unknown-linux-gnu` triple, it removes a compilation flag that's not recognized by `gcc`.

The `optional-backtrace.patch` modifies Rust source code to allow disabling backtrace support via a
cargo feature.

## Known limitations

### Huge binaries in debug profile

Building a crate with debug information results in a massive binary (several MBs), this is because
the debug information of the `std` crate and all its dependencies are included in the binary.
This doesn't occur with native compilation because the crates included in the Rust distribution
are build without debug information. I'm unsure of how to dealt with this, we may need to add a new
option to `cargo` that will force it to compile dependencies without debug information.

For now a workaround is to disable debug information in the debug profile:

```
// Cargo.toml
[profile.debug]
debug = false
```

This reduces the binary size, but the downside is that you won't be able to debug the program using
`gdb`.

### Can't compile the `std` natively

Unimplemented, but it should work in principle.

## TODO

- Currently, the `alloc` crate is always compiled without jemalloc support. Add cargo features that
  will let us pick between no jemalloc, static jemalloc (default) and dynamic jemalloc. These cargo
  features will likely need to be "bubbled up" in the `collections` and `std` crates.

- Currently, the `std` crate has a cargo feature for backtrace support, but the feature is disabled
  by default -- that default should be reversed. It may also be worthwhile to add another feature
  to dynamically link to libbacktrace.

## License

The scripts and patches in this repository are licensed under the MIT license.

See LICENSE-MIT for more details.
