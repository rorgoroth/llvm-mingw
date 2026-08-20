#!/bin/bash

git clean -xdf

CC=clang \
CXX=clang++ \
LLVM_VERSION=22.1.8 \
LLVM_REPOSITORY=https://github.com/rorgoroth/llvm-project.git \
MINGW_W64_VERSION=d7f3c52012c4af4fb526330117d9c86b266018dc \
TOOLCHAIN_ARCHS="x86_64" \
   ./build-all.sh --with-clang --use-linker=lld --thinlto --disable-lldb --disable-lldb-mi --disable-clang-tools-extra --with-default-win32-winnt=0x0A00 --with-default-msvcrt=ucrt --disable-cfguard llvm-x86_64-w64-mingw32

find ./llvm-x86_64-w64-mingw32 -name '*.dll.a' -print -delete

tar -c -I 'zstd -18 -T0' -f 22.1.8-r1.tar.zst llvm-x86_64-w64-mingw32
