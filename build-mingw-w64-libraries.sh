#!/bin/sh
#
# Copyright (c) 2018 Martin Storsjo
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

set -e

: ${ARCHS:=${TOOLCHAIN_ARCHS-x86_64}}

USE_CFLAGS="-O2 -mguard=cf"

while [ $# -gt 0 ]; do
    case "$1" in
    --enable-cfguard)
        USE_CFLAGS="-O2 -mguard=cf"
        ;;
    --disable-cfguard)
        USE_CFLAGS="-O2"
        ;;
    *)
        PREFIX="$1"
        ;;
    esac
    shift
done
if [ -z "$PREFIX" ]; then
    echo "$0 [--enable-cfguard|--disable-cfguard] dest"
    exit 1
fi
mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"
export PATH="$PREFIX/bin:$PATH"
unset CC

if [ ! -d mingw-w64 ] || [ -n "$SYNC" ]; then
    CHECKOUT_ONLY=1 ./build-mingw-w64.sh
fi

cd mingw-w64/mingw-w64-libraries
for lib in winpthreads winstorecompat; do
    cd $lib
    for arch in $ARCHS; do
        [ -z "$CLEAN" ] || rm -rf build-$arch
        mkdir -p build-$arch
        cd build-$arch
        arch_prefix="$PREFIX/$arch-w64-mingw32"
        ../configure --host=$arch-w64-mingw32 --prefix="$arch_prefix" --libdir="$arch_prefix/lib" \
            CFLAGS="$USE_CFLAGS" \
            CXXFLAGS="$USE_CFLAGS"
        make -j8
        make install
        cd ..
        mkdir -p "$arch_prefix/share/mingw32"
        install -m644 COPYING "$arch_prefix/share/mingw32/COPYING.${lib}.txt"
    done
    cd ..
done
