#!/bin/bash

git clean -xdf

./build-all.sh --disable-clang-tools-extra \
               --disable-lldb \
               --disable-cfguard \
               --with-default-msvcrt=ucrt \
               --with-default-win32-winnt=0x0A00 \
               llvm-x86_64-w64-mingw32

tar -c -I 'zstd -18 -T0' -f  19.1.4.tar.zst llvm-x86_64-w64-mingw32
