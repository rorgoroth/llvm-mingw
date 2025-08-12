#!/bin/sh
#
# Copyright (c) 2018 Martin Storsjo
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

set -e

: ${LLVM_VERSION:=21.1.0-rc3}
ASSERTS=OFF
unset HOST
BUILDDIR="build"
LINK_DYLIB=ON
ASSERTSSUFFIX=""
LLDB=ON
CLANG_TOOLS_EXTRA=ON

while [ $# -gt 0 ]; do
    case "$1" in
    --disable-asserts)
        ASSERTS=OFF
        ASSERTSSUFFIX=""
        ;;
    --enable-asserts)
        ASSERTS=ON
        ASSERTSSUFFIX="-asserts"
        ;;
    --with-clang)
        WITH_CLANG=1
        BUILDDIR="$BUILDDIR-withclang"
        ;;
    --thinlto)
        LTO="thin"
        BUILDDIR="$BUILDDIR-thinlto"
        ;;
    --lto)
        LTO="full"
        BUILDDIR="$BUILDDIR-lto"
        ;;
    --disable-dylib)
        LINK_DYLIB=OFF
        ;;
    --full-llvm)
        FULL_LLVM=1
        ;;
    --host=*)
        HOST="${1#*=}"
        ;;
    --disable-lldb)
        unset LLDB
        ;;
    --disable-clang-tools-extra)
        unset CLANG_TOOLS_EXTRA
        ;;
    --no-llvm-tool-reuse)
        NO_LLVM_TOOL_REUSE=1
        ;;
    *)
        PREFIX="$1"
        ;;
    esac
    shift
done
BUILDDIR="$BUILDDIR$ASSERTSSUFFIX"
if [ -z "$CHECKOUT_ONLY" ]; then
    if [ -z "$PREFIX" ]; then
        echo $0 [--enable-asserts] [--with-clang] [--thinlto] [--lto] [--disable-dylib] [--full-llvm] [--disable-lldb] [--disable-clang-tools-extra] [--host=triple] dest
        exit 1
    fi

    mkdir -p "$PREFIX"
    PREFIX="$(cd "$PREFIX" && pwd)"
fi

if [ ! -d llvm-project ]; then
    mkdir llvm-project
    cd llvm-project
    git init
    git remote add origin https://github.com/rorgoroth/llvm-project.git
    cd ..
    CHECKOUT=1
fi

if [ -n "$SYNC" ] || [ -n "$CHECKOUT" ]; then
    cd llvm-project
    # Check if the intended commit or tag exists in the local repo. If it
    # exists, just check it out instead of trying to fetch it.
    # (Redoing a shallow fetch will refetch the data even if the commit
    # already exists locally, unless fetching a tag with the "tag"
    # argument.)
    if git cat-file -e "$LLVM_VERSION" 2>/dev/null; then
        # Exists; just check it out
        git checkout "$LLVM_VERSION"
    else
        case "$LLVM_VERSION" in
        llvmorg-*)
            # If $LLVM_VERSION looks like a tag, fetch it with the
            # "tag" keyword. This makes sure that the local repo
            # gets the tag too, not only the commit itself. This allows
            # later fetches to realize that the tag already exists locally.
            git fetch --depth 1 origin tag "$LLVM_VERSION"
            git checkout "$LLVM_VERSION"
            ;;
        *)
            git fetch --depth 1 origin "$LLVM_VERSION"
            git checkout FETCH_HEAD
            ;;
        esac
    fi
    cd ..
fi

[ -z "$CHECKOUT_ONLY" ] || exit 0

if [ -n "$HOST" ]; then
    case $HOST in
    *-mingw32)
        TARGET_WINDOWS=1
        ;;
    esac
else
    case $(uname) in
    MINGW*)
        TARGET_WINDOWS=1
        ;;
    esac
fi

CMAKEFLAGS="$LLVM_CMAKEFLAGS"

if [ -n "$HOST" ]; then
    ARCH="${HOST%%-*}"

    if [ -n "$WITH_CLANG" ]; then
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_C_COMPILER=clang"
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CXX_COMPILER=clang++"
        CMAKEFLAGS="$CMAKEFLAGS -DLLVM_USE_LINKER=lld"
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_ASM_COMPILER_TARGET=$HOST"
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_C_COMPILER_TARGET=$HOST"
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CXX_COMPILER_TARGET=$HOST"
        if command -v $HOST-strip >/dev/null; then
            CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_STRIP=$(command -v $HOST-strip)"
        fi
    else
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_C_COMPILER=$HOST-gcc"
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CXX_COMPILER=$HOST-g++"
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_SYSTEM_PROCESSOR=$ARCH"
    fi
    case $HOST in
    *-mingw32)
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_SYSTEM_NAME=Windows"
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_RC_COMPILER=$HOST-windres"
        ;;
    *-linux*)
        CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_SYSTEM_NAME=Linux"
        ;;
    *)
        echo "Unrecognized host $HOST"
        exit 1
        ;;
    esac

    native=""
    for dir in llvm-project/llvm/build/bin llvm-project/llvm/build-asserts/bin; do
        if [ -x "$dir/llvm-tblgen.exe" ]; then
            native="$(pwd)/$dir"
            break
        elif [ -x "$dir/llvm-tblgen" ]; then
            native="$(pwd)/$dir"
            break
        fi
    done
    if [ -z "$native" ] && command -v llvm-tblgen >/dev/null; then
        native="$(dirname $(command -v llvm-tblgen))"
    fi

    if [ -n "$native" ] && [ -z "$NO_LLVM_TOOL_REUSE" ]; then
        CMAKEFLAGS="$CMAKEFLAGS -DLLVM_NATIVE_TOOL_DIR=$native"
    fi
    CROSS_ROOT=$(cd $(dirname $(command -v $HOST-gcc))/../$HOST && pwd)
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH=$CROSS_ROOT"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"

    BUILDDIR=$BUILDDIR-$HOST

elif [ -n "$WITH_CLANG" ]; then
    # Build using clang and lld (from $PATH), rather than the system default
    # tools.
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_C_COMPILER=clang"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CXX_COMPILER=clang++"
    CMAKEFLAGS="$CMAKEFLAGS -DLLVM_USE_LINKER=lld"
else
    # Native compilation with the system default compiler.

    # Use a faster linker, if available.
    if command -v ld.lld >/dev/null; then
        CMAKEFLAGS="$CMAKEFLAGS -DLLVM_USE_LINKER=lld"
    elif command -v ld.gold >/dev/null; then
        CMAKEFLAGS="$CMAKEFLAGS -DLLVM_USE_LINKER=gold"
    fi
fi

if [ -n "$COMPILER_LAUNCHER" ]; then
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_C_COMPILER_LAUNCHER=$COMPILER_LAUNCHER"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CXX_COMPILER_LAUNCHER=$COMPILER_LAUNCHER"
fi

if [ -n "$LTO" ]; then
    CMAKEFLAGS="$CMAKEFLAGS -DLLVM_ENABLE_LTO=$LTO"
fi

TOOLCHAIN_ONLY=ON
if [ -n "$FULL_LLVM" ]; then
    TOOLCHAIN_ONLY=OFF
fi

cd llvm-project/llvm

PROJECTS="clang;lld"
if [ -n "$LLDB" ]; then
    PROJECTS="$PROJECTS;lldb"
fi
if [ -n "$CLANG_TOOLS_EXTRA" ]; then
    PROJECTS="$PROJECTS;clang-tools-extra"
fi

[ -z "$CLEAN" ] || rm -rf $BUILDDIR
mkdir -p $BUILDDIR
cd $BUILDDIR
[ -n "$NO_RECONF" ] || rm -rf CMake*
cmake \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_ASSERTIONS=$ASSERTS \
    -DLLVM_ENABLE_PROJECTS="$PROJECTS" \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    -DLLVM_INSTALL_TOOLCHAIN_ONLY=$TOOLCHAIN_ONLY \
    -DLLVM_LINK_LLVM_DYLIB=$LINK_DYLIB \
    -DLLVM_TOOLCHAIN_TOOLS="llvm-ar;llvm-ranlib;llvm-objdump;llvm-rc;llvm-cvtres;llvm-nm;llvm-strings;llvm-readobj;llvm-dlltool;llvm-pdbutil;llvm-objcopy;llvm-strip;llvm-cov;llvm-profdata;llvm-addr2line;llvm-symbolizer;llvm-windres;llvm-ml;llvm-readelf;llvm-size;llvm-cxxfilt;llvm-lib" \
    ${HOST+-DLLVM_HOST_TRIPLE=$HOST} \
    $CMAKEFLAGS \
    ..

cmake --build .
cmake --install . --strip

cp ../LICENSE.TXT $PREFIX
