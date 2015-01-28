#!/bin/bash

TARGET=arm-linux-gnueabihf
TARGET_GCC=$TARGET-gcc
TARGET_LD=$TARGET-ld
TARGET_NM=$TARGET-nm
TARGET_OBJDUMP=$TARGET-objdump

echo --------------------------------------------------------------------------------
echo -- Checking if ghc has been downloaded
echo --------------------------------------------------------------------------------
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

cd ghc

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
./configure --enable-unregisterised --target=$TARGET --with-gcc=$TARGET_GCC -with-ld=$TARGET_LD --with-nm=$TARGET_NM --with-objdump=$TARGET_OBJDUMP

# build
echo --------------------------------------------------------------------------------
echo -- Building
echo --------------------------------------------------------------------------------
make -j4
make -j4

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
