#!/bin/sh
#
# Copyright (c) 2020 Martin Storsjo
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

: ${LLDB_MI_VERSION:=f1fea743bf06a99b6e7f74085bd8c8db47999df5}
BUILDDIR=build
unset HOST

while [ $# -gt 0 ]; do
    case "$1" in
    --host=*)
        HOST="${1#*=}"
        ;;
    *)
        PREFIX="$1"
        ;;
    esac
    shift
done
if [ -z "$PREFIX" ]; then
    echo $0 [--host=<triple>] dest
    exit 1
fi

mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"

if [ ! -d lldb-mi ]; then
    git clone https://github.com/lldb-tools/lldb-mi.git
    CHECKOUT=1
fi

if [ -n "$SYNC" ] || [ -n "$CHECKOUT" ]; then
    cd lldb-mi
    [ -z "$SYNC" ] || git fetch
    git checkout $LLDB_MI_VERSION
    cd ..
fi

export LLVM_DIR="$PREFIX"

# Try to find/guess the builddir under the llvm buildtree next by.
# If LLVM was built without LLVM_INSTALL_TOOLCHAIN_ONLY, and the LLVM
# installation directory hasn't been stripped, we should point the build there.
# But as this isn't necessarily the case, point to the LLVM build directory
# instead (which hopefully hasn't been removed yet).
LLVM_SRC="$(pwd)/llvm-project/llvm"
if [ -d "$LLVM_SRC" ]; then
    SUFFIX=${HOST+-}$HOST
    DIRS=""
    cd llvm-project/llvm
    for dir in build*$SUFFIX; do
        if [ -z "$SUFFIX" ]; then
            case $dir in
            *linux*|*mingw32*)
                continue
                ;;
            esac
        fi
        if [ -d "$dir" ]; then
            DIRS="$DIRS $dir"
        fi
    done
    if [ -n "$DIRS" ]; then
        dir="$(ls -td $DIRS | head -1)"
        export LLVM_DIR="$LLVM_SRC/$dir"
        echo Using $LLVM_DIR as LLVM build dir
        break
    else
        # No build directory found; this is ok if the installed prefix is a
        # full (development) install of LLVM. Warn that we didn't find what
        # we were looking for.
        echo Warning, did not find a suitable LLVM build dir, assuming $PREFIX contains LLVM development files >&2
    fi
    cd ../..
fi

if [ -n "$HOST" ]; then
    BUILDDIR=$BUILDDIR-$HOST

    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_C_COMPILER=$HOST-gcc"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CXX_COMPILER=$HOST-g++"
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

    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH=$LLVM_DIR"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"
fi

cd lldb-mi

[ -z "$CLEAN" ] || rm -rf $BUILDDIR
mkdir -p $BUILDDIR
cd $BUILDDIR
[ -n "$NO_RECONF" ] || rm -rf CMake*
cmake \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    $CMAKEFLAGS \
    ..

cmake --build .
cmake --install . --strip
