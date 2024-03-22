#!/bin/bash

git clean -xdf

./build-all.sh --disable-clang-tools-extra \
               --disable-lldb \
               --disable-cfguard \
               --with-default-msvcrt=ucrt \
               --with-default-win32-winnt=0x0A00 \
               llvm-x86_64-w64-mingw32

apack 18.1.2-r3.tar.xz llvm-x86_64-w64-mingw32
