APP_NAME = Wheel Browser
BUNDLE_NAME = Wheel Browser.app
BUILD_DIR = .build/arm64-apple-macosx/release
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)

.PHONY: build install clean

build:
	swift build -c release
	@echo "Creating app bundle..."
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp "$(BUILD_DIR)/WheelBrowser" "$(BUNDLE_DIR)/Contents/MacOS/"
	@cp Info.plist "$(BUNDLE_DIR)/Contents/"
	@cp Sources/WheelBrowser/Resources/AppIcon.icns "$(BUNDLE_DIR)/Contents/Resources/"
	@# Copy any bundled resources from Swift PM
	@if [ -d "$(BUILD_DIR)/WheelBrowser_WheelBrowser.bundle" ]; then \
		cp -R "$(BUILD_DIR)/WheelBrowser_WheelBrowser.bundle" "$(BUNDLE_DIR)/Contents/Resources/"; \
	fi
	@echo "Built: $(BUNDLE_DIR)"

install: build
	@echo "Installing to /Applications..."
	@rm -rf "/Applications/$(BUNDLE_NAME)"
	@cp -R "$(BUNDLE_DIR)" /Applications/
	@echo "Installed: /Applications/$(BUNDLE_NAME)"

clean:
	swift package clean
	@rm -rf "$(BUNDLE_DIR)"
