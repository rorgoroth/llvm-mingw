#!/bin/bash

./build-all.sh --disable-cfguard \
               --disable-clang-tools-extra \
               --disable-dylib \
               --disable-lldb \
               --disable-lldb-mi \
               --with-default-msvcrt=ucrt \
               --with-default-win32-winnt=0x0A00 \
               llvm-x86_64-w64-mingw32

#cp -v llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/libc++.a \
#      llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/libstdc++.a

#apack 18.1.2.tar.xz llvm-x86_64-w64-mingw32
