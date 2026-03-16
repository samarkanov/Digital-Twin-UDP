# Makefile for managing the UDP-SSE project

.PHONY: build up down logs ps clean release help

# Default target
default: up

help:
	@echo "Available commands:"
	@echo "  make build         - Build the MATLAB binary and gather dependencies"
	@echo "  make up            - Start the services locally"
	@echo "  make down          - Stop services and cleanup"
	@echo "  make release TAG=v1.0.0 - Build, zip, and create a GitHub Release"
	@echo "  make clean         - Remove Docker images and build artifacts"

# Build everything: generate binary/libs locally
build:
	@echo "Generating C++ code and gathering dependencies locally..."
	matlab-batch "openProject('.'); generate_cpp_code"

# Create a release on GitHub (requires 'gh' CLI)
release:
	@if [ -z "$(TAG)" ]; then echo "Error: TAG is required. Use 'make release TAG=vX.Y.Z'"; exit 1; fi
	@echo "Starting release process for $(TAG)..."
	$(MAKE) build
	@echo "Zipping build artifacts..."
	zip -r bld.zip bld/
	@echo "Creating GitHub Release and uploading bld.zip..."
	gh release create $(TAG) bld.zip --title "Release $(TAG)" --notes "Automated release containing MATLAB binaries."
	@rm bld.zip
	@echo "Release $(TAG) created successfully!"

up:
	docker compose up -d

down:
	docker compose down
	sudo rm -rf shared_data/

logs:
	docker compose logs -f

ps:
	docker compose ps

clean:
	docker compose down --rmi all --volumes --remove-orphans
	rm -rf bld/
