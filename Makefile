# Local source builds only. This file never fetches or publishes anything.
-include Makefile.local
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
DEVELOPER_ID_IDENTITY ?= Developer ID Application: Ningxiang Sun (2E5N3Q45BG)
APP := build/DerivedData/Build/Products/Release/Spotifly.app
BASELINE := 6077b513205f5a602ec08df0ceb5dcb4f08bc66d

.PHONY: build verify check-source check-soloist
build: check-source check-soloist
	env DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -quiet -project Spotifly.xcodeproj -scheme Spotifly -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -disableAutomaticPackageResolution CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(DEVELOPER_ID_IDENTITY)" DEVELOPMENT_TEAM=2E5N3Q45BG CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
	python3 scripts/stage-soloist.py --app "$(APP)"
	codesign --force --options runtime --timestamp --entitlements Spotifly/Spotifly.entitlements --sign "$(DEVELOPER_ID_IDENTITY)" "$(APP)"
	codesign --verify --deep --strict --verbose=2 "$(APP)"

check-source:
	git merge-base --is-ancestor $(BASELINE) HEAD

verify:
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	codesign -dvv --entitlements - "$(APP)"

check-soloist:
	python3 scripts/stage-soloist.py
