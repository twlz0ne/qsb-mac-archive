#!/bin/sh

# PostBuild.sh
#
# Copyright 2007-2008 Google Inc. All rights reserved.

# Script that runs postbuild for QSB
# Generates breakpad symbols

"${SRCROOT}/BuildScripts/GenerateBreakpadSymbols.sh"
