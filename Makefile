SHELL := /bin/zsh
XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SCHEME ?= FileMailer
CONFIGURATION ?= Debug
DERIVED_DATA ?= build/DerivedData
SOURCE_PACKAGES ?= build/SourcePackages
CODE_SIGNING_ALLOWED ?= NO
RELEASE_CODE_SIGN_IDENTITY ?= Developer ID Application
RELEASE_CODE_SIGN_STYLE ?= Manual
RELEASE_DEVELOPMENT_TEAM ?= $(shell sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([^[:space:]]+).*$$/\1/p' Config/Local.xcconfig 2>/dev/null | head -1)

.PHONY: bootstrap audit-public check-app-store generate fixtures test build run archive archive-app-store export-app-store package notarize verify-release clean clean-space

bootstrap:
	@command -v xcodegen >/dev/null
	@test -d "$(XCODE_DEVELOPER_DIR)"
	@echo "XcodeGen and Xcode developer directory are available."

audit-public:
	zsh Scripts/audit_public_source.sh

check-app-store:
	python3 Scripts/check_app_store.py

generate:
	xcodegen generate

fixtures:
	python3 Scripts/generate_test_fixtures.py

test:
	python3 Scripts/check_localizations.py
	cd Packages/FileMailerCore && \
		DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" \
		CLANG_MODULE_CACHE_PATH=/private/tmp/FileMailerModuleCache \
		SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/FileMailerModuleCache \
		xcrun swift test

build:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" \
	CLANG_MODULE_CACHE_PATH=/private/tmp/FileMailerXcodeModuleCache \
	SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/FileMailerXcodeModuleCache \
	xcodebuild -project FileMailer.xcodeproj -scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" -destination "generic/platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
		CODE_SIGNING_ALLOWED="$(CODE_SIGNING_ALLOWED)" build

run: build
	open "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/FileMailer.app"

archive:
	@test "$(CODE_SIGNING_ALLOWED)" = "YES"
	@test -n "$(RELEASE_DEVELOPMENT_TEAM)"
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcodebuild \
		-project FileMailer.xcodeproj -scheme "$(SCHEME)" \
		-configuration Release -destination "generic/platform=macOS" \
		-archivePath build/FileMailer.xcarchive \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
		CODE_SIGN_STYLE="$(RELEASE_CODE_SIGN_STYLE)" \
		CODE_SIGN_IDENTITY="$(RELEASE_CODE_SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM="$(RELEASE_DEVELOPMENT_TEAM)" \
		archive

archive-app-store: check-app-store
	@test "$(CODE_SIGNING_ALLOWED)" = "YES"
	@test -n "$(RELEASE_DEVELOPMENT_TEAM)"
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcodebuild \
		-project FileMailer.xcodeproj -scheme "$(SCHEME)" \
		-configuration AppStore -destination "generic/platform=macOS" \
		-archivePath build/FileMailer-AppStore.xcarchive \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
		DEVELOPMENT_TEAM="$(RELEASE_DEVELOPMENT_TEAM)" archive

export-app-store: archive-app-store
	XCODE_DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" zsh Scripts/export_app_store.sh

package: archive
	ditto -c -k --keepParent build/FileMailer.xcarchive/Products/Applications/FileMailer.app build/FileMailer.zip
	(cd build && shasum -a 256 FileMailer.zip > FileMailer.zip.sha256)
	zsh Scripts/package_dmg.sh \
		build/FileMailer.xcarchive/Products/Applications/FileMailer.app \
		build/FileMailer.dmg
	(cd build && shasum -a 256 FileMailer.dmg > FileMailer.dmg.sha256)
	cp SBOM.spdx.json build/FileMailer.spdx.json

notarize: package
	@test -n "$$NOTARY_KEYCHAIN_PROFILE"
	xcrun notarytool submit build/FileMailer.zip \
		--keychain-profile "$$NOTARY_KEYCHAIN_PROFILE" --wait
	xcrun stapler staple build/FileMailer.xcarchive/Products/Applications/FileMailer.app
	ditto -c -k --keepParent build/FileMailer.xcarchive/Products/Applications/FileMailer.app build/FileMailer.zip
	(cd build && shasum -a 256 FileMailer.zip > FileMailer.zip.sha256)
	zsh Scripts/package_dmg.sh \
		build/FileMailer.xcarchive/Products/Applications/FileMailer.app \
		build/FileMailer.dmg
	xcrun notarytool submit build/FileMailer.dmg \
		--keychain-profile "$$NOTARY_KEYCHAIN_PROFILE" --wait
	xcrun stapler staple build/FileMailer.dmg
	(cd build && shasum -a 256 FileMailer.dmg > FileMailer.dmg.sha256)

verify-release:
	codesign --verify --strict --verbose=2 build/FileMailer.xcarchive/Products/Applications/FileMailer.app/Contents/PlugIns/FileMailer\ Finder\ Extension.appex
	codesign --verify --deep --strict --verbose=2 build/FileMailer.xcarchive/Products/Applications/FileMailer.app
	codesign -dv --verbose=4 build/FileMailer.xcarchive/Products/Applications/FileMailer.app 2>&1 | grep -q "TeamIdentifier=$(RELEASE_DEVELOPMENT_TEAM)"
	spctl --assess --type execute --verbose=4 build/FileMailer.xcarchive/Products/Applications/FileMailer.app
	xcrun stapler validate build/FileMailer.xcarchive/Products/Applications/FileMailer.app
	xcrun stapler validate build/FileMailer.dmg
	(cd build && shasum -a 256 -c FileMailer.zip.sha256)
	(cd build && shasum -a 256 -c FileMailer.dmg.sha256)

clean:
	xcodebuild -project FileMailer.xcodeproj -scheme "$(SCHEME)" clean

clean-space:
	zsh Scripts/clean_project_caches.sh
