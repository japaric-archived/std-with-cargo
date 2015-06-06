#!/bin/bash

set -e
set -x

# install OpenWRT SDK
pushd ..
mkdir openwrt
cd openwrt
wget https://downloads.openwrt.org/barrier_breaker/14.07/ar71xx/generic/OpenWrt-SDK-ar71xx-for-linux-x86_64-gcc-4.8-linaro_uClibc-0.9.33.2.tar.bz2
tar jxf *.tar.bz2 --strip-components=1
export STAGING_DIR="$PWD/staging_dir"
export PATH="$PWD/$(echo staging_dir/toolchain-*/bin):$PATH"
mips-openwrt-linux-gcc -v
popd

./fetch-and-patch-rust.sh

set +e
set +x
