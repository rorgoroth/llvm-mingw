#!/bin/bash

git clean -xdf

./build-all.sh --disable-clang-tools-extra \
               --disable-lldb \
               --disable-cfguard \
               --with-default-msvcrt=ucrt \
               --with-default-win32-winnt=0x0A00 \
               llvm-x86_64-w64-mingw32

cp -v llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/libc++.a \
      llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/libstdc++.a

apack 18.1.0-rc1.tar.xz llvm-x86_64-w64-mingw32
