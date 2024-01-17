#!/bin/bash

git=$(sh /etc/profile; which git)
git_release_version=$("$git" describe --tags --abbrev=0)

dots="${git_release_version//[^s|.]}"

number_commits_since_release_version=$("$git" rev-list $git_release_version..HEAD --count)

target_plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
dsym_plist="$DWARF_DSYM_FOLDER_PATH/$DWARF_DSYM_FILE_NAME/Contents/Info.plist"

for plist in "$target_plist" "$dsym_plist"; do
  if [ -f "$plist" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $number_commits_since_release_version" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${git_release_version#*v}" "$plist"
  fi
done
