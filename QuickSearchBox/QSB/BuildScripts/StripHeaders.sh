#!/bin/sh
#
# StripHeaders.sh
#
# Copyright 2007-2008 Google Inc. All rights reserved.


# Strip "*.h" files
find "${BUILD_ROOT}/${CONFIGURATION}/${WRAPPER_NAME}" -iname '*.h' -delete

# Strip "Headers" links
find "${BUILD_ROOT}/${CONFIGURATION}/${WRAPPER_NAME}" -iname 'Headers' -type l -delete

# Strip "Headers" directories
find "${BUILD_ROOT}/${CONFIGURATION}/${WRAPPER_NAME}" -iname 'Headers' -type d -prune -delete


