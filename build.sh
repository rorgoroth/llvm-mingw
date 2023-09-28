#!/bin/bash

rm -rf llvm-x86_64-w64-mingw32
rm -rf *.tar.xz

./build-all.sh --disable-lldb \
               --disable-clang-tools-extra \
               --with-default-msvcrt=ucrt \
               --with-default-win32-winnt=0x0A00 \
               --enable-cfguard \
               llvm-x86_64-w64-mingw32

rm -v llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/*.dll.a
cp -v llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/libc++.a llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/libstdc++.a

apack llvm-x86_64-w64-mingw32_17.0.1.tar.xz llvm-x86_64-w64-mingw32
