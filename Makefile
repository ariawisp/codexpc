SVC=com.yourorg.codexpc

.PHONY: build run install uninstall health smoke logs status reload warmup codex-test

build:
	cd daemon-swift && swift build -c debug

run:
	./daemon-swift/.build/debug/codexpcd

install:
	./packaging/install-agent.sh

uninstall:
	./packaging/uninstall-agent.sh

health:
	cd cli-swift && swift run -c release codexpc-cli --health

# Usage: make smoke CHECKPOINT=/path/to/model.bin
smoke:
	cd cli-swift && swift run -c release codexpc-cli --checkpoint "$(CHECKPOINT)" --prompt "hello" --temperature 0.0 --max-tokens 0

logs:
	log show --predicate 'subsystem == "com.yourorg.codexpc"' --last $${LAST:-10m} --style syslog --info --debug

status:
	launchctl list | rg com.yourorg.codexpc || true
	launchctl print gui/$$(id -u)/com.yourorg.codexpc || true

reload:
	launchctl bootout gui/$$(id -u)/com.yourorg.codexpc 2>/dev/null || true
	launchctl unload $$HOME/Library/LaunchAgents/com.yourorg.codexpc.plist 2>/dev/null || true
	launchctl load -w $$HOME/Library/LaunchAgents/com.yourorg.codexpc.plist
	launchctl kickstart -k gui/$$(id -u)/com.yourorg.codexpc 2>/dev/null || true

# Usage: make warmup CHECKPOINT=/path/to/model.bin
warmup:
	mkdir -p $$HOME/.local/codexpc/etc
	@echo "$(CHECKPOINT)" > $$HOME/.local/codexpc/etc/warmup-checkpoint
	@echo "Wrote warmup checkpoint to $$HOME/.local/codexpc/etc/warmup-checkpoint"

# Usage: make codex-test CHECKPOINT=/path/to/model.bin
codex-test:
	cd ../codex/codex-rs && SDKROOT="$$(xcrun --show-sdk-path)" MACOSX_DEPLOYMENT_TARGET=13.0 CODEXPC_CHECKPOINT="$(CHECKPOINT)" cargo test -p codex-core --test mac_codexpc_integration -- --ignored --nocapture
