#!/bin/bash
#
#  Localization.sh
#  Copyright 2009 Google Inc.
#  
#  Perform all the ops required to localize a QSB into any localizations
#  we have in googlemac/localization/GoogleQSB/*

set -o errexit
set -o nounset
set -o verbose

# Additional languages that TC generates but we don't want to include
LANGUAGE_BLACKLIST=( de_CH en_IE en_IN en_SG zh zh_HK )

# runs through a directory copying .strings files into the appropriate locales
# GOOGLE_L10N_TARGET and UNLOCALIZED_RESOURCES_FOLDER_PATH need to be set before
# calling this function.
function localize {
  if [ -d "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/English.lproj" ];
  then
      echo Localizing $GOOGLE_L10N_TARGET
      "${GOOGLE_MAC_TOOLS}/l10n/pulse_extract.py"
      "${GOOGLE_MAC_TOOLS}/l10n/generator.py" --source "${GOOGLE_MAC_ROOT}/localization" --blacklist zh
      chmod u+w "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
      rm -Rf "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/en_US.lproj"
      mv "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/English.lproj" "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/en_US.lproj"
      echo "${GOOGLE_MAC_ROOT}/localization/GoogleQSB/${GOOGLE_L10N_TARGET}"/*
      for LOCALIZATION in "${GOOGLE_MAC_ROOT}/localization/GoogleQSB/${GOOGLE_L10N_TARGET}"/*
      do
          LOCALIZATION_BASE=`basename "${LOCALIZATION}"`
          BLACKLISTED="NO"
          for LANGUAGE in ${LANGUAGE_BLACKLIST[@]}
          do
            if [ $LANGUAGE == ${LOCALIZATION_BASE} ]; then
              BLACKLISTED="YES"
            fi
          done
          if [ "${BLACKLISTED}" == "NO" ]; then
            echo "Localizing language ${LOCALIZATION_BASE}"
            LOCALIZATION_DST="${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/${LOCALIZATION_BASE}.lproj"
            mkdir -p "${LOCALIZATION_DST}"
            echo /Developer/Library/Xcode/Plug-ins/CoreBuildTasks.xcplugin/Contents/Resources/copystrings --validate --inputencoding UTF-8 --outputencoding UTF-16 --outdir "${LOCALIZATION_DST}" "${LOCALIZATION}"/*.strings
            /Developer/Library/Xcode/Plug-ins/CoreBuildTasks.xcplugin/Contents/Resources/copystrings --validate --inputencoding UTF-8 --outputencoding UTF-16 --outdir "${LOCALIZATION_DST}" "${LOCALIZATION}"/*.strings
            echo /usr/bin/plutil -lint "${LOCALIZATION_DST}"/*.strings
            /usr/bin/plutil -lint "${LOCALIZATION_DST}"/*.strings
          else
            echo "Skipping blacklisted language ${LOCALIZATION_BASE}"
          fi
      done
      mv "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/en_US.lproj" "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/English.lproj"
  fi
}

GOOGLE_L10N_TARGET="GoogleExternalQSB"
# UNLOCALIZED_RESOURCES_FOLDER_PATH is already set up for us by Xcode
localize

# Go running through all of our plugins localizing them 
PLUGINS_FOLDER_PATH="Quick Search Box.app/Contents/PlugIns"
for PLUGIN in "${CONFIGURATION_BUILD_DIR}/${PLUGINS_FOLDER_PATH}"/*.hgs
do
  GOOGLE_L10N_TARGET=`basename "${PLUGIN}" ".hgs"`
  UNLOCALIZED_RESOURCES_FOLDER_PATH="${PLUGINS_FOLDER_PATH}/${GOOGLE_L10N_TARGET}.hgs/Contents/Resources" 
  localize
done

# Go running through all of our frameworks localizing them
FRAMEWORKS_FOLDER_PATH="Quick Search Box.app/Contents/Frameworks"
for FRAMEWORK in "${CONFIGURATION_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"/*.framework
do
  GOOGLE_L10N_TARGET=`basename "${FRAMEWORK}" ".framework"`
  UNLOCALIZED_RESOURCES_FOLDER_PATH="${FRAMEWORKS_FOLDER_PATH}/${GOOGLE_L10N_TARGET}.framework/Resources" 
  localize
done

