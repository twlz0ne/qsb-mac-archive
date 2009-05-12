#!/bin/sh
# GenerateBreakpadSymbols.sh
#
# Note: This script is intended to be used for targets using the
# BreakpadExecutable.xcconfig file. 
#
# Copyright 2007-2008 Google Inc. All rights reserved.

# Optional single command-line argument to override the symbol file base name

set -o errexit
set -o nounset
set -o verbose

GOOGLE_MAC_BREAKPAD_TOOLS="${SRCROOT}/../externals/GoogleBreakpad"

if [ $# -eq 1 ]; then
  SYMBOL_FILE_BASE_NAME="$1"
else
  SYMBOL_FILE_BASE_NAME="${EXECUTABLE_NAME}"
fi

BREAKPAD_FILE="${BUILT_PRODUCTS_DIR}/${SYMBOL_FILE_BASE_NAME}_${GOOGLE_VERSIONINFO_LONG}"
BREAKPAD_FILE_PPC="${BREAKPAD_FILE}_ppc.breakpad"
BREAKPAD_FILE_386="${BREAKPAD_FILE}_i386.breakpad"

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
      "${GOOGLE_MAC_BREAKPAD_TOOLS}/dump_syms" -a ppc "${INPUT_DWARF_FILE}" > "${BREAKPAD_FILE_PPC}"
    fi
    if [ "${INPUT_DWARF_FILE}" -nt "${BREAKPAD_FILE_386}" ]; then
      "${GOOGLE_MAC_BREAKPAD_TOOLS}/dump_syms" -a i386 "${INPUT_DWARF_FILE}" > "${BREAKPAD_FILE_386}"
    fi
  else
    if [ "${INPUT_FILE_386}" -nt "${BREAKPAD_FILE_386}" ]; then
      "${GOOGLE_MAC_BREAKPAD_TOOLS}/dump_syms" -a i386 "${INPUT_FILE_386}" > "${BREAKPAD_FILE_386}"
    fi
    if [ "${INPUT_FILE_PPC}" -nt "${BREAKPAD_FILE_PPC}" ]; then
      "${GOOGLE_MAC_BREAKPAD_TOOLS}/dump_syms" -a ppc "${INPUT_FILE_PPC}" > "${BREAKPAD_FILE_PPC}"
    fi
  fi  
fi
