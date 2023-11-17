#!/bin/bash

git=$(sh /etc/profile; which git)
version=$("$git" describe --tags --abbrev=0)
destination_path="KompleteSynthesia.${version}/"

rm "KompleteSynthesia.${version}.dmg"
rm -rf "${destination_path}"

mkdir "${destination_path}"
cp -R KompleteSynthesia.app "${destination_path}"
cp LICENSE "${destination_path}"
cp -R README.rtfd "${destination_path}"
cp -R SETUP.rtfd "${destination_path}"

create-dmg \
  --volname "KompleteSynthesia" \
  --background "KompleteSynthesia_DMG_Background.png" \
  --window-pos 200 120 \
  --window-size 704 604 \
  --icon-size 100 \
  --text-size 15 \
  --hide-extension "KompleteSynthesia.app" \
  --app-drop-link 500 320 \
  --icon "KompleteSynthesia.app" 190 320 \
  --icon .background 100 470 \
  --icon LICENSE 370 470 \
  --icon SETUP.rtfd 470 470 \
  --icon README.rtfd 570 470 \
  "KompleteSynthesia.${version}.dmg" \
  "${destination_path}"

rm -rf "${destination_path}"
