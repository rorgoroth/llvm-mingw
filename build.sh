#!/bin/sh

./build-all.sh --host-clang --disable-dylib --disable-lldb --disable-lldb-mi --disable-clang-tools-extra --with-default-win32-winnt=0x0A00 --with-default-msvcrt=ucrt --disable-cfguard build

find ./build -iname '*.dll' -print -delete
