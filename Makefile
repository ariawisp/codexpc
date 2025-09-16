SVC=com.yourorg.codexpc

.PHONY: build run install uninstall

build:
	cd daemon-swift && swift build -c debug

run:
	./daemon-swift/.build/debug/codexpcd

install:
	./packaging/install-agent.sh

uninstall:
	./packaging/uninstall-agent.sh

