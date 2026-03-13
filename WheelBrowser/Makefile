APP_NAME = Wheel Browser
BUNDLE_NAME = Wheel Browser.app
NOTES_APP_NAME = Wheel Notes
NOTES_BUNDLE_NAME = Wheel Notes.app
BUILD_DIR = .build/arm64-apple-macosx/release
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)
NOTES_BUNDLE_DIR = $(BUILD_DIR)/$(NOTES_BUNDLE_NAME)
NOTE_EDITOR_DIR = ../NoteEditorWeb

.PHONY: build build-note-editor build-notes install clean

build-note-editor:
	@if [ -d "$(NOTE_EDITOR_DIR)/node_modules" ]; then \
		npm --prefix "$(NOTE_EDITOR_DIR)" run build; \
	elif [ -f "Sources/WheelNotesCore/Resources/NoteEditor/index.html" ]; then \
		echo "Using existing NoteEditor bundle. Run 'npm --prefix $(NOTE_EDITOR_DIR) install && npm --prefix $(NOTE_EDITOR_DIR) run build' to refresh it."; \
	else \
		echo "NoteEditor bundle missing. Run 'npm --prefix $(NOTE_EDITOR_DIR) install && npm --prefix $(NOTE_EDITOR_DIR) run build' first."; \
		exit 1; \
	fi

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

build-notes: build-note-editor
	swift build -c release --product WheelNotes
	@echo "Creating notes app bundle..."
	@rm -rf "$(NOTES_BUNDLE_DIR)"
	@mkdir -p "$(NOTES_BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(NOTES_BUNDLE_DIR)/Contents/Resources"
	@cp "$(BUILD_DIR)/WheelNotes" "$(NOTES_BUNDLE_DIR)/Contents/MacOS/"
	@cp Info.plist "$(NOTES_BUNDLE_DIR)/Contents/"
	@cp Sources/WheelBrowser/Resources/AppIcon.icns "$(NOTES_BUNDLE_DIR)/Contents/Resources/"
	@if [ -d "$(BUILD_DIR)/WheelBrowser_WheelNotes.bundle" ]; then \
		cp -R "$(BUILD_DIR)/WheelBrowser_WheelNotes.bundle" "$(NOTES_BUNDLE_DIR)/Contents/Resources/"; \
	fi
	@echo "Built: $(NOTES_BUNDLE_DIR)"

install: build
	@echo "Installing to /Applications..."
	@rm -rf "/Applications/$(BUNDLE_NAME)"
	@cp -R "$(BUNDLE_DIR)" /Applications/
	@echo "Installed: /Applications/$(BUNDLE_NAME)"

clean:
	swift package clean
	@rm -rf "$(BUNDLE_DIR)"
	@rm -rf "$(NOTES_BUNDLE_DIR)"
