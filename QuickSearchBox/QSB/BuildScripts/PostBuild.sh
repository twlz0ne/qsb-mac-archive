#!/bin/sh

# PostBuild.sh
#
# Copyright 2007-2008 Google Inc. All rights reserved.

# Script that runs postbuild for QSB
# Strips out headers, and generates breakpad symbols

"${SRCROOT}/BuildScripts/StripHeaders.sh"
"${SRCROOT}/BuildScripts/GenerateBreakpadSymbols.sh"
