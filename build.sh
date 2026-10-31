#!/usr/bin/env bash
# EH3D-IOS-CONTROL build launcher: the tests of the package (the screens are built with Xcode). GPL-3.0-or-later.
cd "$(dirname "$0")" && swift test
