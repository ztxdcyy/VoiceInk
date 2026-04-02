APP_NAME = Voiceink
BUNDLE_ID = com.voiceink.app
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
SIGNING_IDENTITY = Voiceink Dev

.PHONY: build run install release qa clean reset-permissions setup-cert

build:
	swift build -c release
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	cp "Sources/Voiceink/Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	codesign --force --sign "$(SIGNING_IDENTITY)" "$(APP_BUNDLE)"

run: build
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	open "$(APP_BUNDLE)"

install: build
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

release:
	swift build -c release
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	cp "Sources/Voiceink/Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	@echo "Release build done (unsigned)."
	cd "$(BUILD_DIR)" && zip -r "$(APP_NAME).zip" "$(APP_NAME).app"
	@echo "Package ready: $(BUILD_DIR)/$(APP_NAME).zip"
	@echo "⚠️  Users need to run: xattr -cr Voiceink.app"

reset-permissions:
	@echo "Resetting TCC Accessibility for $(BUNDLE_ID)..."
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@echo "Done. Re-run the app and re-authorize in System Settings."

qa: build
	@echo "--- Voiceink QA Prep ---"
	@echo "1) App bundle: $(APP_BUNDLE)"
	@test -f "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" && echo "2) Binary exists: OK" || (echo "2) Binary missing" && exit 1)
	@test -f "$(APP_BUNDLE)/Contents/Info.plist" && echo "3) Info.plist exists: OK" || (echo "3) Info.plist missing" && exit 1)
	@echo "4) Manual QA checklist: QA_CHECKLIST.md"

clean:
	swift package clean
	rm -rf .build

setup-cert:
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "Voiceink Dev"; then \
		echo "Certificate 'Voiceink Dev' already exists."; \
	else \
		echo "Creating self-signed code signing certificate 'Voiceink Dev'..."; \
		openssl req -x509 -newkey rsa:2048 \
			-keyout /tmp/voiceink-dev.key -out /tmp/voiceink-dev.crt \
			-days 3650 -nodes -subj "/CN=Voiceink Dev" \
			-config <(printf '[req]\ndistinguished_name=dn\nx509_extensions=cs\nprompt=no\n[dn]\nCN=Voiceink Dev\n[cs]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n'); \
		openssl rsa -in /tmp/voiceink-dev.key -out /tmp/voiceink-dev-legacy.key -traditional; \
		security import /tmp/voiceink-dev.crt -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign; \
		security import /tmp/voiceink-dev-legacy.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign; \
		security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/voiceink-dev.crt; \
		rm -f /tmp/voiceink-dev.key /tmp/voiceink-dev.crt /tmp/voiceink-dev-legacy.key; \
		echo "Done. Verify with: security find-identity -v -p codesigning"; \
	fi
