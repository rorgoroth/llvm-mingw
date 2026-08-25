#!/bin/bash

git clean -xdf

CC=clang \
CXX=clang++ \
LLVM_VERSION=llvmorg-23.1.0 \
MINGW_W64_VERSION=b0c3cce6a14965dbac1713e619c811a149044dcd \
TOOLCHAIN_ARCHS="x86_64" \
   ./build-all.sh --with-clang --use-linker=lld --thinlto --disable-lldb --disable-lldb-mi --disable-clang-tools-extra --with-default-win32-winnt=0x0A00 --with-default-msvcrt=ucrt --disable-cfguard llvm-x86_64-w64-mingw32

find ./llvm-x86_64-w64-mingw32 -name '*.dll.a' -print -delete

tar -c -I 'zstd -18 -T0' -f 23.1.0.tar.zst llvm-x86_64-w64-mingw32
