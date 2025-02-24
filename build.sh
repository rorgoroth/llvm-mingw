#!/bin/bash

git clean -xdf

./build-all.sh  --disable-dylib \
                --disable-lldb \
                --disable-lldb-mi \
                --disable-clang-tools-extra \
                --with-default-win32-winnt=0x0A00 \
                --with-default-msvcrt=ucrt \
                --disable-cfguard \
               llvm-x86_64-w64-mingw32

tar -c -I 'zstd -18 -T0' -f  19.1.7.tar.zst llvm-x86_64-w64-mingw32
