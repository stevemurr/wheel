# SqliteVec Package Makefile
#
# Downloads sqlite-vec source files from the official releases

VERSION := 0.1.6
RELEASE_URL := https://github.com/asg017/sqlite-vec/releases/download/v$(VERSION)
AMALGAMATION := sqlite-vec-$(VERSION)-amalgamation.zip

SOURCES_DIR := Sources/CSqliteVec
INCLUDE_DIR := $(SOURCES_DIR)/include

.PHONY: download clean test build

# Download and extract sqlite-vec source files
download:
	@echo "Downloading sqlite-vec v$(VERSION)..."
	@curl -L -o /tmp/$(AMALGAMATION) $(RELEASE_URL)/$(AMALGAMATION)
	@echo "Extracting..."
	@unzip -o -j /tmp/$(AMALGAMATION) "sqlite-vec.c" -d $(SOURCES_DIR)/
	@unzip -o -j /tmp/$(AMALGAMATION) "sqlite-vec.h" -d $(INCLUDE_DIR)/
	@rm /tmp/$(AMALGAMATION)
	@echo "Done! sqlite-vec v$(VERSION) installed."

# Clean downloaded files (revert to placeholders)
clean:
	@echo "Cleaning sqlite-vec source files..."
	@rm -f $(SOURCES_DIR)/sqlite-vec.c
	@rm -f $(INCLUDE_DIR)/sqlite-vec.h
	@echo "Creating placeholder..."
	@echo '/* PLACEHOLDER - run "make download" */' > $(SOURCES_DIR)/sqlite-vec.c
	@echo '#error "Run make download to fetch sqlite-vec"' >> $(SOURCES_DIR)/sqlite-vec.c

# Build the package
build: download
	swift build

# Run tests
test: download
	swift test

# Show help
help:
	@echo "SqliteVec Package"
	@echo ""
	@echo "Usage:"
	@echo "  make download  - Download sqlite-vec source files"
	@echo "  make build     - Build the Swift package"
	@echo "  make test      - Run tests"
	@echo "  make clean     - Remove downloaded files"
	@echo ""
	@echo "Current version: $(VERSION)"
