# Makefile for pomobeats installation
.PHONY: install

install:
	mkdir -p $(HOME)/pomobeats/music/work $(HOME)/pomobeats/music/break
	@echo "Music directories created at $(HOME)/pomobeats/music/work and $(HOME)/pomobeats/music/break"
	mkdir -p $(HOME)/bin
	@if [ -f script.sh ]; then \
		cp script.sh $(HOME)/bin/pomobeats; \
		chmod +x $(HOME)/bin/pomobeats; \
	else \
		echo "Error: script.sh not found!"; \
		exit 1; \
	fi