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

BUILD_STATIC=ON
BUILD_SHARED=ON
CFGUARD_CFLAGS="-mguard=cf"

while [ $# -gt 0 ]; do
    if [ "$1" = "--disable-shared" ]; then
        BUILD_SHARED=OFF
    elif [ "$1" = "--enable-shared" ]; then
        BUILD_SHARED=ON
    elif [ "$1" = "--disable-static" ]; then
        BUILD_STATIC=OFF
    elif [ "$1" = "--enable-static" ]; then
        BUILD_STATIC=ON
    elif [ "$1" = "--enable-cfguard" ]; then
        CFGUARD_CFLAGS="-mguard=cf"
    elif [ "$1" = "--disable-cfguard" ]; then
        CFGUARD_CFLAGS=
    else
        PREFIX="$1"
    fi
    shift
done
if [ -z "$PREFIX" ]; then
    echo "$0 [--disable-shared] [--disable-static] [--enable-cfguard|--disable-cfguard] dest"
    exit 1
fi

mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"

export PATH="$PREFIX/bin:$PATH"

: ${ARCHS:=${TOOLCHAIN_ARCHS-x86_64}}

if [ ! -d llvm-project/libunwind ] || [ -n "$SYNC" ]; then
    CHECKOUT_ONLY=1 ./build-llvm.sh
fi

cd llvm-project

cd runtimes

for arch in $ARCHS; do
    [ -z "$CLEAN" ] || rm -rf build-$arch
    mkdir -p build-$arch
    cd build-$arch
    [ -n "$NO_RECONF" ] || rm -rf CMake*
    cmake \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX/$arch-w64-mingw32" \
        -DCMAKE_C_COMPILER=$arch-w64-mingw32-clang \
        -DCMAKE_CXX_COMPILER=$arch-w64-mingw32-clang++ \
        -DCMAKE_CXX_COMPILER_TARGET=$arch-w64-windows-gnu \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_C_COMPILER_WORKS=TRUE \
        -DCMAKE_CXX_COMPILER_WORKS=TRUE \
        -DCMAKE_AR="$PREFIX/bin/llvm-ar" \
        -DCMAKE_RANLIB="$PREFIX/bin/llvm-ranlib" \
        -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
        -DLIBUNWIND_USE_COMPILER_RT=TRUE \
        -DLIBUNWIND_ENABLE_SHARED=$BUILD_SHARED \
        -DLIBUNWIND_ENABLE_STATIC=$BUILD_STATIC \
        -DLIBCXX_USE_COMPILER_RT=ON \
        -DLIBCXX_ENABLE_SHARED=$BUILD_SHARED \
        -DLIBCXX_ENABLE_STATIC=$BUILD_STATIC \
        -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=TRUE \
        -DLIBCXX_CXX_ABI=libcxxabi \
        -DLIBCXX_LIBDIR_SUFFIX="" \
        -DLIBCXX_INCLUDE_TESTS=FALSE \
        -DLIBCXX_INSTALL_MODULES=ON \
        -DLIBCXX_INSTALL_MODULES_DIR="$PREFIX/share/libc++/v1" \
        -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=FALSE \
        -DLIBCXXABI_USE_COMPILER_RT=ON \
        -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
        -DLIBCXXABI_ENABLE_SHARED=OFF \
        -DLIBCXXABI_LIBDIR_SUFFIX="" \
        -DCMAKE_C_FLAGS_INIT="$CFGUARD_CFLAGS" \
        -DCMAKE_CXX_FLAGS_INIT="$CFGUARD_CFLAGS" \
        ..

    cmake --build .
    cmake --install .
    cd ..
done
