#!/bin/bash

git clean -xdf

./build-all.sh --disable-clang-tools-extra \
               --disable-lldb \
               --disable-cfguard \
               --with-default-msvcrt=ucrt \
               --with-default-win32-winnt=0x0A00 \
               --thinlto \
               llvm-x86_64-w64-mingw32

cp -v llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/libc++.a \
      llvm-x86_64-w64-mingw32/x86_64-w64-mingw32/lib/libstdc++.a

apack 17.0.6-r4.tar.xz llvm-x86_64-w64-mingw32
