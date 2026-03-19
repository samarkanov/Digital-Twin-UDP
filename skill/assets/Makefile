# Makefile for managing the Digital Twin ecosystem

.PHONY: build up down logs ps clean release help

# Default target
default: up

# Build: generate binary/libs locally (requires MATLAB)
build:
	@echo "Generating C++ code and gathering dependencies locally..."
	matlab -batch "run('matlab/build_portable_binary.m')"

# Create a release on GitHub (requires 'gh' CLI)
release:
	@if [ -z "$(TAG)" ]; then echo "Error: TAG is required. Use 'make release TAG=vX.Y.Z'"; exit 1; fi
	@echo "Starting release process for $(TAG)..."
	$(MAKE) build
	zip -r bld.zip bld/
	gh release create $(TAG) bld.zip --title "Release $(TAG)" --notes "Automated release containing MATLAB binaries."
	@rm bld.zip
	@echo "Release $(TAG) created successfully!"

# Start the services locally (pulls from GHCR if bld/ is missing)
up:
	@if [ ! -d "bld" ]; then \
		echo "Notice: 'bld/' directory not found. Pulling images from GHCR..."; \
		docker compose pull; \
		docker compose up -d --no-build; \
	else \
		docker compose up -d; \
	fi

down:
	docker compose down

clean:
	docker compose down --rmi all --volumes --remove-orphans
	rm -rf bld/
