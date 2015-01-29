#!/bin/bash

TARGET=arm-linux-gnueabihf
TARGET_GCC=$TARGET-gcc
TARGET_LD=$TARGET-ld
TARGET_NM=$TARGET-nm
TARGET_OBJDUMP=$TARGET-objdump

BUILD_GCC=gcc
BUILD_ARCH=$($BUILD_GCC -v 2>&1 | grep ^Target: | cut -f 2 -d ' ')
MAKEFLAGS=${MAKEFLAGS:--j4}

echo --------------------------------------------------------------------------------
echo -- Checking if needed programs are installed
echo --------------------------------------------------------------------------------
function check_progs {
    if ! command -v $1 >/dev/null
    then
        echo Need $1
        exit 1
    else
        echo Have $1
    fi
}

check_progs git
check_progs curl
check_progs tar
check_progs make
check_progs $TARGET_GCC
check_progs patch

echo --------------------------------------------------------------------------------
echo -- Checking if ghc has been downloaded
echo --------------------------------------------------------------------------------
<<EOF
if ! [ -d "./ghc" ]
then
    echo -- Getting from GitHub
    git clone https://github.com/ghc/ghc.git
else
    echo -- Repo has been downloaded... updating
    cd ghc
    git pull
    cd ..
fi
EOF

GHC_RELEASE=7.8.4
GHC_TAR_FILE=ghc-${GHC_RELEASE}-src.tar.xz
GHC_TAR_PATH="./${GHC_TAR_FILE}"
GHC_SRC="./ghc-${GHC_RELEASE}"
if ! [ -f "GHC_TAR_FILE" ]; then
    echo Downloading ghc $GHC_RELEASE
    curl -o "$GHC_TAR_FILE" https://downloads.haskell.org/~ghc/$GHC_RELEASE/$GHC_TAR_FILE
fi
if ! [ -d "$GHC_SRC" ]; then
    tar -xJf "$GHC_TAR_FILE"
fi

## Borrowed the downloading and building scripts from ghc-android (https://github.com/neurocyte/ghc-android)
# downloading, cross-building, and installing ncurses
NCURSES_RELEASE=5.9
NCURSES_TAR_FILE=ncurses-${NCURSES_RELEASE}.tar.gz
NCURSES_TAR_PATH="./${NCURSES_TAR_FILE}"
NCURSES_SRC="./ncurses-${NCURSES_RELEASE}"
if ! [ -f "$NCURSES_TAR_FILE" ]; then
    echo Downloading ncurses $NCURSES_RELEASE
    curl -o "${NCURSES_TAR_FILE}" http://ftp.gnu.org/pub/gnu/ncurses/${NCURSES_TAR_FILE}
fi
if ! [ -d "$NCURSES_SRC" ]; then
    tar xf "$NCURSES_TAR_FILE"
fi

#if ! [ -e "$NDK_ADDON_PREFIX/lib/libncurses.a" ]; then
    cd $NCURSES_SRC
    if ! [ -e "lib/libncurses.a" ]
    then
        ./configure --host=$TARGET --build=$BUILD_ARCH --with-build-cc=$BUILD_GCC --enable-static --disable-shared --without-manpages --without-cxx-binding
        echo '#undef HAVE_LOCALE_H' >> "$NCURSES_SRC/include/ncurses_cfg.h" # TMP hack
        patch ./misc/run_tic.sh < ../run_tic.sh.patch # from http://stackoverflow.com/questions/25258930/cross-compiling-ncurses-5-9-for-arm-form-lib-not-found
        make $MAKEFLAGS
    fi
    sudo make install prefix=/usr/$TARGET
    cd ..
#fi

<<EOF
# downloading, cross-building, and installing GMP
GMP_RELEASE=6.0.0a
GMP_TAR_FILE=gmp-${GMP_RELEASE}.tar.xz
GMP_TAR_PATH="./${GMP_TAR_FILE}"
GMP_SRC="./gmp-6.0.0"
if ! [ -d "$GMP_SRC" ]
then
    echo Downloading gmp $GMP_RELEASE
    curl -o "${TARDIR}/${GMP_TAR_FILE}" https://gmplib.org/download/gmp/${GMP_TAR_FILE}
    check_md5 "$GMP_TAR_PATH" "$GMP_MD5"
    (cd $NDK_ADDON_SRC; tar xf "$TARDIR/$GMP_TAR_FILE")
fi
if ! [ -e "$NDK_ADDON_PREFIX/lib/libgmp.a" ]
then
    pushd $GMP_SRC > /dev/null
    if ! [ -e ".libs/libgmp.a" ]
    then
        ./configure --prefix="$NDK_ADDON_PREFIX" --host=$NDK_TARGET --build=$BUILD_ARCH --with-build-cc=$BUILD_GCC --enable-static --disable-shared
        make $MAKEFLAGS
    fi
    make install
    popd > /dev/null
fi
EOF

cd $GHC_SRC

# initial setup with new repo or to grab stuff needed
echo --------------------------------------------------------------------------------
echo -- Syncing
echo --------------------------------------------------------------------------------
./sync-all get
./boot

# setup make file
echo --------------------------------------------------------------------------------
echo -- Setting up the makefile
echo --------------------------------------------------------------------------------
if ! [ -d "mk/${TARGET}_build.mk" ]
then
    touch "mk/${TARGET}_build.mk"
fi
cat > mk/$TARGET_build.mk <<EOF
# -------- Miscellaneous variables --------------------------------------------

# Set to V = 0 to get prettier build output.
# Please use V = 1 when reporting GHC bugs.
V = 1

GhcLibWays = \$(if \$(filter \$(DYNAMIC_GHC_PROGRAMS),YES),v dyn,v)

# Only use -fasm by default on platforms that support it.
GhcFAsm = \$(if \$(filter \$(GhcWithNativeCodeGen),YES),-fasm,)

# quick-cross profile from build.mk
SRC_HC_OPTS        = -H64m -O0
GhcStage1HcOpts    = -O
GhcStage2HcOpts    = -O0 -fllvm
GhcLibHcOpts       = -O -fllvm
SplitObjs          = NO
HADDOCK_DOCS       = NO
BUILD_DOCBOOK_HTML = NO
BUILD_DOCBOOK_PS   = NO
BUILD_DOCBOOK_PDF  = NO
INTEGER_LIBRARY    = integer-simple
Stage1Only         = YES

DYNAMIC_BY_DEFAULT   = NO
DYNAMIC_GHC_PROGRAMS = NO

# -----------------------------------------------------------------------------
# Other settings that might be useful

# NoFib settings
NoFibWays =
STRIP_CMD = :
EOF

# do configure
echo --------------------------------------------------------------------------------
echo -- Configuring
echo --------------------------------------------------------------------------------
./configure --target=$TARGET --with-gcc=$TARGET_GCC -with-ld=$TARGET_LD --with-nm=$TARGET_NM --with-objdump=$TARGET_OBJDUMP --enable-unregisterised

# build
echo --------------------------------------------------------------------------------
echo -- Building
echo --------------------------------------------------------------------------------
export C_INCLUDE_PATH=/usr/$TARGET/include # http://stackoverflow.com/questions/18592674/install-haskell-terminfo-in-windows
make $MAKEFLAGS

echo --------------------------------------------------------------------------------
echo -- Testing
echo --------------------------------------------------------------------------------
cd ..
touch test.hs
cat > test.hs <<EOF
main = putStrLn "Hello World"
EOF

./ghc/in-place/ghc-stage1 test.hs
file test
