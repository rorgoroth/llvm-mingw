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

: ${LLVM_VERSION:=19.1.6}
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
    *)
        PREFIX="$1"
        ;;
    esac
    shift
done
BUILDDIR="$BUILDDIR$ASSERTSSUFFIX"
if [ -z "$CHECKOUT_ONLY" ]; then
    if [ -z "$PREFIX" ]; then
        echo $0 [--enable-asserts] [--thinlto] [--lto] [--disable-dylib] [--full-llvm] [--disable-lldb] [--disable-clang-tools-extra] [--host=triple] dest
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
    if git cat-file -e "$LLVM_VERSION" 2> /dev/null; then
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

CMAKEFLAGS="$LLVM_CMAKEFLAGS"

if [ -n "$HOST" ]; then
    ARCH="${HOST%%-*}"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_C_COMPILER=$HOST-gcc"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_CXX_COMPILER=$HOST-g++"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_SYSTEM_PROCESSOR=$ARCH"
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
fi

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


    if [ -n "$native" ]; then
        CMAKEFLAGS="$CMAKEFLAGS -DLLVM_NATIVE_TOOL_DIR=$native"
    fi
    CROSS_ROOT=$(cd $(dirname $(command -v $HOST-gcc))/../$HOST && pwd)
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH=$CROSS_ROOT"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY"
    CMAKEFLAGS="$CMAKEFLAGS -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"

    BUILDDIR=$BUILDDIR-$HOST

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
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_SHARED_LIBS=OFF \
    -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
    -DCLANG_DEFAULT_LINKER=lld \
    -DCLANG_DEFAULT_RTLIB=compiler-rt \
    -DCLANG_DEFAULT_UNWINDLIB=libunwind \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_TOOL_AMDGPU_ARCH_BUILD=OFF \
    -DCLANG_TOOL_APINOTES_TEST_BUILD=OFF \
    -DCLANG_TOOL_ARCMT_TEST_BUILD=OFF \
    -DCLANG_TOOL_C_ARCMT_TEST_BUILD=OFF \
    -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
    -DCLANG_TOOL_CLANG_CHECK_BUILD=OFF \
    -DCLANG_TOOL_CLANG_DIFF_BUILD=OFF \
    -DCLANG_TOOL_CLANG_EXTDEF_MAPPING_BUILD=OFF \
    -DCLANG_TOOL_CLANG_FORMAT_BUILD=OFF \
    -DCLANG_TOOL_CLANG_FORMAT_VS_BUILD=OFF \
    -DCLANG_TOOL_CLANG_FUZZER_BUILD=OFF \
    -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
    -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
    -DCLANG_TOOL_CLANG_OFFLOAD_BUNDLER_BUILD=OFF \
    -DCLANG_TOOL_CLANG_OFFLOAD_PACKAGER_BUILD=OFF \
    -DCLANG_TOOL_CLANG_REFACTOR_BUILD=OFF \
    -DCLANG_TOOL_CLANG_RENAME_BUILD=OFF \
    -DCLANG_TOOL_CLANG_REPL_BUILD=OFF \
    -DCLANG_TOOL_CLANG_SCAN_DEPS_BUILD=OFF \
    -DCLANG_TOOL_CLANG_SHLIB_BUILD=OFF \
    -DCLANG_TOOL_DIAGTOOL_BUILD=OFF \
    -DCLANG_TOOL_LIBCLANG_BUILD=OFF \
    -DCLANG_TOOL_NVPTX_ARCH_BUILD=OFF \
    -DCLANG_TOOL_SCAN_BUILD_BUILD=OFF \
    -DCLANG_TOOL_SCAN_BUILD_PY_BUILD=OFF \
    -DCLANG_TOOL_SCAN_VIEW_BUILD=OFF \
    -DLLD_DEFAULT_LD_LLD_IS_MINGW=ON \
    -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_BUILD_TESTS=OFF \
    -DLLVM_ENABLE_ASSERTIONS=$ASSERTS \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_PROJECTS="$PROJECTS" \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_UTILS=OFF \
    -DLLVM_INSTALL_TOOLCHAIN_ONLY=$TOOLCHAIN_ONLY \
    -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    -DLLVM_TOOL_BUGPOINT_BUILD=OFF \
    -DLLVM_TOOL_BUGPOINT_PASSES_BUILD=OFF \
    -DLLVM_TOOL_DSYMUTIL_BUILD=OFF \
    -DLLVM_TOOL_DXIL_DIS_BUILD=OFF \
    -DLLVM_TOOL_GOLD_BUILD=OFF \
    -DLLVM_TOOL_LLC_BUILD=OFF \
    -DLLVM_TOOL_LLI_BUILD=OFF \
    -DLLVM_TOOL_LLVM_AS_BUILD=OFF \
    -DLLVM_TOOL_LLVM_AS_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_BCANALYZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_C_TEST_BUILD=OFF \
    -DLLVM_TOOL_LLVM_CAT_BUILD=OFF \
    -DLLVM_TOOL_LLVM_CFI_VERIFY_BUILD=OFF \
    -DLLVM_TOOL_LLVM_COV_BUILD=OFF \
    -DLLVM_TOOL_LLVM_CXXDUMP_BUILD=OFF \
    -DLLVM_TOOL_LLVM_CXXFILT_BUILD=OFF \
    -DLLVM_TOOL_LLVM_CXXMAP_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DEBUGINFO_ANALYZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DEBUGINFOD_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DEBUGINFOD_FIND_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DIFF_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DIS_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DIS_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DLANG_DEMANGLE_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DWARFDUMP_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DWARFUTIL_BUILD=OFF \
    -DLLVM_TOOL_LLVM_DWP_BUILD=OFF \
    -DLLVM_TOOL_LLVM_EXEGESIS_BUILD=OFF \
    -DLLVM_TOOL_LLVM_EXTRACT_BUILD=OFF \
    -DLLVM_TOOL_LLVM_GSYMUTIL_BUILD=OFF \
    -DLLVM_TOOL_LLVM_IFS_BUILD=OFF \
    -DLLVM_TOOL_LLVM_ISEL_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_ITANIUM_DEMANGLE_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_JITLINK_BUILD=OFF \
    -DLLVM_TOOL_LLVM_JITLISTENER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LIBTOOL_DARWIN_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LINK_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LIPO_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
    -DLLVM_TOOL_LLVM_MC_ASSEMBLE_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_MC_BUILD=OFF \
    -DLLVM_TOOL_LLVM_MC_DISASSEMBLE_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_MCA_BUILD=OFF \
    -DLLVM_TOOL_LLVM_MICROSOFT_DEMANGLE_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_MODEXTRACT_BUILD=OFF \
    -DLLVM_TOOL_LLVM_MT_BUILD=OFF \
    -DLLVM_TOOL_LLVM_OPT_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_PROFGEN_BUILD=OFF \
    -DLLVM_TOOL_LLVM_READTAPI_BUILD=OFF \
    -DLLVM_TOOL_LLVM_REDUCE_BUILD=OFF \
    -DLLVM_TOOL_LLVM_REMARKUTIL_BUILD=OFF \
    -DLLVM_TOOL_LLVM_RTDYLD_BUILD=OFF \
    -DLLVM_TOOL_LLVM_RUST_DEMANGLE_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_SHLIB_BUILD=OFF \
    -DLLVM_TOOL_LLVM_SIM_BUILD=OFF \
    -DLLVM_TOOL_LLVM_SPECIAL_CASE_LIST_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_SPLIT_BUILD=OFF \
    -DLLVM_TOOL_LLVM_STRESS_BUILD=OFF \
    -DLLVM_TOOL_LLVM_TLI_CHECKER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_UNDNAME_BUILD=OFF \
    -DLLVM_TOOL_LLVM_XRAY_BUILD=OFF \
    -DLLVM_TOOL_LLVM_YAML_NUMERIC_PARSER_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_LLVM_YAML_PARSER_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_OBJ2YAML_BUILD=OFF \
    -DLLVM_TOOL_OPT_VIEWER_BUILD=OFF \
    -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
    -DLLVM_TOOL_SANCOV_BUILD=OFF \
    -DLLVM_TOOL_SANSTATS_BUILD=OFF \
    -DLLVM_TOOL_SPIRV_TOOLS_BUILD=OFF \
    -DLLVM_TOOL_VERIFY_USELISTORDER_BUILD=OFF \
    -DLLVM_TOOL_VFABI_DEMANGLE_FUZZER_BUILD=OFF \
    -DLLVM_TOOL_XCODE_TOOLCHAIN_BUILD=OFF \
    -DLLVM_USE_LINKER=lld \
    -DLLVM_TOOLCHAIN_TOOLS="llvm-ar;llvm-ranlib;llvm-objdump;llvm-rc;llvm-cvtres;llvm-nm;llvm-strings;llvm-readobj;llvm-dlltool;llvm-pdbutil;llvm-objcopy;llvm-strip;llvm-cov;llvm-profdata;llvm-addr2line;llvm-symbolizer;llvm-windres;llvm-ml;llvm-readelf;llvm-size;llvm-cxxfilt" \
    ${HOST+-DLLVM_HOST_TRIPLE=$HOST} \
    $CMAKEFLAGS \
    ..

cmake --build .
cmake --install . --strip

cp ../LICENSE.TXT $PREFIX
