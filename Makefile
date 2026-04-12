APP_NAME = Speakin
BUNDLE_ID = com.speakin.app
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
SIGNING_IDENTITY = Speakin Dev

.PHONY: build run install release qa clean reset-permissions setup-cert

build:
	swift build -c release
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	cp "Sources/Speakin/Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	cp "Sources/Speakin/Resources/AppIcon.icns" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_capsule.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_capsule@2x.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_menubar.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_menubar@2x.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_menubar.svg" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_icon_32.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_icon_32@2x.png" "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --sign "$(SIGNING_IDENTITY)" "$(APP_BUNDLE)"

run: build
	@# Graceful shutdown: send SIGTERM then wait for process to fully exit
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		pgrep -x $(APP_NAME) >/dev/null 2>&1 || break; \
		sleep 0.3; \
	done
	@# Force kill if still alive after 3 seconds
	@pkill -9 -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.3
	open "$(APP_BUNDLE)"

install: build
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

release:
	swift build -c release
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	cp "Sources/Speakin/Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	cp "Sources/Speakin/Resources/AppIcon.icns" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_capsule.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_capsule@2x.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_menubar.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_menubar@2x.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_menubar.svg" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_icon_32.png" "$(APP_BUNDLE)/Contents/Resources/"
	cp "Sources/Speakin/Resources/bird_icon_32@2x.png" "$(APP_BUNDLE)/Contents/Resources/"
	@echo "Release build done (unsigned)."
	@# --- Create styled DMG ---
	@rm -rf "$(BUILD_DIR)/dmg-staging"
	@rm -f "$(BUILD_DIR)/$(APP_NAME)-rw.dmg" "$(BUILD_DIR)/$(APP_NAME).dmg"
	@mkdir -p "$(BUILD_DIR)/dmg-staging"
	@cp -R "$(APP_BUNDLE)" "$(BUILD_DIR)/dmg-staging/"
	@ln -s /Applications "$(BUILD_DIR)/dmg-staging/Applications"
	@# Create a read-write DMG first
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder "$(BUILD_DIR)/dmg-staging" \
		-ov -format UDRW \
		"$(BUILD_DIR)/$(APP_NAME)-rw.dmg"
	@rm -rf "$(BUILD_DIR)/dmg-staging"
	@# Mount, style with AppleScript, unmount
	hdiutil attach "$(BUILD_DIR)/$(APP_NAME)-rw.dmg" -readwrite -noverify -noautoopen
	@sleep 1
	osascript scripts/style-dmg.applescript "$(APP_NAME)"
	@sync
	@sleep 1
	hdiutil detach "/Volumes/$(APP_NAME)" -quiet
	@# Convert to compressed read-only DMG
	hdiutil convert "$(BUILD_DIR)/$(APP_NAME)-rw.dmg" \
		-format UDZO -o "$(BUILD_DIR)/$(APP_NAME).dmg"
	@rm -f "$(BUILD_DIR)/$(APP_NAME)-rw.dmg"
	@echo "Package ready: $(BUILD_DIR)/$(APP_NAME).dmg"
	@echo "⚠️  Users need to run: xattr -cr /Applications/Speakin.app"

reset-permissions:
	@echo "Resetting TCC Accessibility for $(BUNDLE_ID)..."
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@echo "Done. Re-run the app and re-authorize in System Settings."

qa: build
	@echo "--- Speakin QA Prep ---"
	@echo "1) App bundle: $(APP_BUNDLE)"
	@test -f "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" && echo "2) Binary exists: OK" || (echo "2) Binary missing" && exit 1)
	@test -f "$(APP_BUNDLE)/Contents/Info.plist" && echo "3) Info.plist exists: OK" || (echo "3) Info.plist missing" && exit 1)
	@echo "4) Manual QA checklist: QA_CHECKLIST.md"

clean:
	swift package clean
	rm -rf .build

setup-cert:
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "$(SIGNING_IDENTITY)"; then \
		echo "Certificate '$(SIGNING_IDENTITY)' already exists."; \
	else \
		echo "Creating self-signed code signing certificate '$(SIGNING_IDENTITY)'..."; \
		openssl req -x509 -newkey rsa:2048 \
			-keyout /tmp/speakin-dev.key -out /tmp/speakin-dev.crt \
			-days 3650 -nodes -subj "/CN=$(SIGNING_IDENTITY)" \
			-config <(printf '[req]\ndistinguished_name=dn\nx509_extensions=cs\nprompt=no\n[dn]\nCN=$(SIGNING_IDENTITY)\n[cs]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n'); \
		openssl rsa -in /tmp/speakin-dev.key -out /tmp/speakin-dev-legacy.key -traditional; \
		security import /tmp/speakin-dev.crt -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign; \
		security import /tmp/speakin-dev-legacy.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign; \
		security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/speakin-dev.crt; \
		rm -f /tmp/speakin-dev.key /tmp/speakin-dev.crt /tmp/speakin-dev-legacy.key; \
		echo "Done. Verify with: security find-identity -v -p codesigning"; \
	fi
