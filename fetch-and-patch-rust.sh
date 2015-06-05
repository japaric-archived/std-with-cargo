#!/bin/bash

# Downloads a snapshot of rust-lang/rust that matches your installed `rustc`
# version, and patches it so the `std` crate can be cross compiled using
# `cargo`

set -e
set -x

# find out `rustc` version
HASH=$(rustc -Vv | sed -n 3p | cut -d ' ' -f2)

# fetch rust
wget "https://github.com/rust-lang/rust/archive/${HASH}.zip"
unzip ${HASH}.zip
rm ${HASH}.zip
mv rust-${HASH} rust

# fetch compiler-rt
# XXX this is not 100% correct because this compiler-rt snapshot may not be the
# right one for the above `rustc` hash, but since the compiler-rt submodule
# hasn't been updated for several months, this should be OK in practice
HASH=58ab642c30d9f97735d5745b5d01781ee199c6ae
cd rust/src
rmdir compiler-rt
wget "https://github.com/rust-lang/compiler-rt/archive/${HASH}.zip"
unzip ${HASH}.zip
mv compiler-rt-${HASH} compiler-rt
rm ${HASH}.zip

# patch
cd ..
curl -s https://raw.githubusercontent.com/japaric/std-with-cargo/master/cargo-ify.patch | patch -p1
curl -s https://raw.githubusercontent.com/japaric/std-with-cargo/master/optional-backtrace.patch | patch -p1
curl -s https://raw.githubusercontent.com/japaric/std-with-cargo/master/remove-mno-compact-eh-flag.patch | patch -p1
