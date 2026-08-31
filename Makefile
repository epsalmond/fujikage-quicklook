XCODEGEN ?= xcodegen
DERIVED := build
APP := $(DERIVED)/Build/Products/Release/FujikageQL.app
INSTALL_DIR := $(HOME)/Applications
TEAM := KA3Y4C7M3R
SIGNING := DEVELOPMENT_TEAM=$(TEAM) CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"

.PHONY: generate test debug release install reset-ql

generate:
	$(XCODEGEN) generate

# FUJIKAGE_TEST_RAF=/path/to/DSCF0001.RAF make test  runs the real-camera-file test.
test: generate
	xcodebuild -project FujikageQL.xcodeproj -scheme FujikageQL -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' $(SIGNING) -allowProvisioningUpdates FUJIKAGE_TEST_RAF="$(FUJIKAGE_TEST_RAF)" test

debug: generate
	xcodebuild -project FujikageQL.xcodeproj -scheme FujikageQL -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' $(SIGNING) -allowProvisioningUpdates build

release: generate
	xcodebuild -project FujikageQL.xcodeproj -scheme FujikageQL -configuration Release -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' $(SIGNING) CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -allowProvisioningUpdates build

install: release
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/FujikageQL.app"
	cp -R "$(APP)" "$(INSTALL_DIR)/FujikageQL.app"
	pluginkit -a "$(INSTALL_DIR)/FujikageQL.app/Contents/PlugIns/FujikageQLPreview.appex"
	pluginkit -a "$(INSTALL_DIR)/FujikageQL.app/Contents/PlugIns/FujikageQLThumbnail.appex"
	pluginkit -e use -i com.epsalmond.fujikage.quicklook.preview
	pluginkit -e use -i com.epsalmond.fujikage.quicklook.thumbnail
	open "$(INSTALL_DIR)/FujikageQL.app"

reset-ql:
	qlmanage -r
	qlmanage -r cache
	killall QuickLookUIService 2>/dev/null || true
	killall Finder 2>/dev/null || true
