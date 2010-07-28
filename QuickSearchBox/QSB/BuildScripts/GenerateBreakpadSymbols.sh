#!/bin/sh
# GenerateBreakpadSymbols.sh
#
# Note: This script is intended to be used for targets using the
# BreakpadExecutable.xcconfig file.
#
# Copyright 2007-2010 Google Inc. All rights reserved.

# Optional single command-line argument to override the symbol file base name

set -o errexit
set -o nounset
set -o verbose

#Expected location for dump_syms
DUMP_SYMS_PATH="${SRCROOT}/../externals/breakpad/src/tools/mac/dump_syms/build/Debug/dump_syms"
#Root of dump_syms project
DUMP_SYMS_SRCROOT="${SRCROOT}/../externals/breakpad/src/tools/mac/dump_syms"

if [ $# -eq 1 ]; then
  SYMBOL_FILE_BASE_NAME="$1"
else
  SYMBOL_FILE_BASE_NAME="${EXECUTABLE_NAME}"
fi

BREAKPAD_FILE="${BUILT_PRODUCTS_DIR}/${SYMBOL_FILE_BASE_NAME}_${GOOGLE_VERSIONINFO_LONG}"
BREAKPAD_FILE_PPC="${BREAKPAD_FILE}_ppc.breakpad"
BREAKPAD_FILE_386="${BREAKPAD_FILE}_i386.breakpad"

# Check to see if dump_syms exists
if [ ! -f "${DUMP_SYMS_PATH}" ]; then
  # Build it if it doesn't.
  pushd ${DUMP_SYMS_SRCROOT}
  xcodebuild -project dump_syms.xcodeproj -target dump_syms -configuration Debug OTHER_CFLAGS="" SDKROOT[arch=*]=macosx10.6
  popd
fi

# Handle clean vs build (not usually used, but could be if used as a separate
# target).
if [ "${ACTION}" == "clean" ]; then
  rm -f "${BREAKPAD_FILE_PPC}"
  rm -f "${BREAKPAD_FILE_386}"
else
  # Generate breakpad symbols from the backing (pre-lipo) binary that will
  # never be stripped. We use the "normal" build variant because that's the one
  # users expect (and build variants with other names are deprecated anyway)

  # Input binary files for each architecture
  INPUT_FILE_PPC="${OBJECT_FILE_DIR_normal}/ppc/${EXECUTABLE_NAME}"
  INPUT_FILE_386="${OBJECT_FILE_DIR_normal}/i386/${EXECUTABLE_NAME}"

  # Input DWARF binary file
  INPUT_DWARF_FILE="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}"

  # Test for the DWARF file existing - if this is a stabs build, those
  # DWARF_DSYM* vars won't be set
  if [ -e "${INPUT_DWARF_FILE}" ];  then
  # Only rebuild if we need to
    if [ "${INPUT_DWARF_FILE}" -nt "${BREAKPAD_FILE_PPC}" ]; then
      "${DUMP_SYMS_PATH}" -a ppc "${INPUT_DWARF_FILE}" > "${BREAKPAD_FILE_PPC}"
    fi
    if [ "${INPUT_DWARF_FILE}" -nt "${BREAKPAD_FILE_386}" ]; then
      "${DUMP_SYMS_PATH}" -a i386 "${INPUT_DWARF_FILE}" > "${BREAKPAD_FILE_386}"
    fi
    # When building with a dSYM bundle, Xcode goes through the following steps
    # near the end of the build:
    # 1. GeneratedSYMFile - reads debug information from executable and writes
    # it out to the dSYM file
    # 2. Generates Breakpad symbols by calling into the custom script
    # 3. Runs /usr/bin/touch on the target binary
    # 4. Strips the target

    # If you Build a target(NOT rebuild), usually none of these happen if the
    # target is up to date.  However I found that, by creating a dummy project
    # that is set to both "strip the linked product", and "generate a dSYM
    # file", and then doing the following:

    # A. Build the target
    # B. Wait about a minute, then run /usr/bin/touch on the binary
    # C. Build the target(NOT rebuild - just want XCode to do things it thinks
    #    needs to be done)

    # I find that XCode reruns the GenerateDSYMFile step, because the binary is
    # newer than the dSYM bundle.  But the binary has been stripped, so the dSYM
    # bundle is overwritten with empty DWARF data.

    # If Xcode is going to compare the timestamps of these two files, and it
    # touches one of them during the build, it should touch both.
    # rdar://7091133
    # The touch below is the fix to the above.
    touch "${INPUT_DWARF_FILE}"
  else
    if [ "${INPUT_FILE_386}" -nt "${BREAKPAD_FILE_386}" ]; then
      "${DUMP_SYMS_PATH}" -a i386 "${INPUT_FILE_386}" > "${BREAKPAD_FILE_386}"
    fi
    if [ "${INPUT_FILE_PPC}" -nt "${BREAKPAD_FILE_PPC}" ]; then
      "${DUMP_SYMS_PATH}" -a ppc "${INPUT_FILE_PPC}" > "${BREAKPAD_FILE_PPC}"
    fi
  fi
fi

ERROR_HEADER="GenerateBreakpadSymbols.sh:0:"
if [ ! -f "${BREAKPAD_FILE_386}" ]; then
  echo ${ERROR_HEADER} error: Unable to generate "${BREAKPAD_FILE_386}"
  exit 1
fi

if [ ! -f "${BREAKPAD_FILE_PPC}" ]; then
  echo ${ERROR_HEADER} error: Unable to generate "${BREAKPAD_FILE_PPC}"
  exit 1
fi
