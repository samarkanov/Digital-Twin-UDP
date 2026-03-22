# Makefile for managing the UDP-SSE project

.PHONY: build up-prod up-dev down logs ps clean release help

# Extract license file path from config.toml and strip potential trailing space
MLM_LICENSE_PATH := $(shell sed -n 's/^\s*matlab_license_file = "\(.*\)"/\1/p' config.toml | xargs)

# Define variables for Docker Compose. If no license is found, use a harmless placeholder for the volume and enable online licensing.
ifneq ($(MLM_LICENSE_PATH),)
    # Inside container, we'll mount it to a fixed location
    INTERNAL_LICENSE_PATH := /home/matlab/license.lic
    export MLM_LICENSE_FILE := $(INTERNAL_LICENSE_PATH)
    export LICENSE_MOUNT := $(MLM_LICENSE_PATH):$(INTERNAL_LICENSE_PATH):ro
    export MWI_USE_EXISTING_LICENSE := True
else
    export MLM_LICENSE_FILE :=
    export LICENSE_MOUNT := .:/home/matlab/.license_placeholder:ro
    export MWI_USE_EXISTING_LICENSE := False
endif

# Default target
default: up-prod

# Sync config.toml and derived variables to .env for docker compose
.env: config.toml Makefile
	@echo "MLM_LICENSE_FILE=$(MLM_LICENSE_FILE)" > .env
	@echo "LICENSE_MOUNT=$(LICENSE_MOUNT)" >> .env
	@echo "MWI_USE_EXISTING_LICENSE=$(MWI_USE_EXISTING_LICENSE)" >> .env

help:
	@echo "Available commands:"
	@echo "  make build         - Build the MATLAB binary and gather dependencies"
	@echo "  make up-prod       - Start full stack including production Digital Twin binary"
	@echo "  make up-dev        - Start stack with MATLAB interactive development container"
	@echo "  make down          - Stop services and cleanup"
	@echo "  make release TAG=v1.0.0 - Build, zip, and create a GitHub Release"
	@echo "  make clean         - Remove Docker images and build artifacts"

# Build everything: generate binary/libs locally
build:
	@echo "Generating C++ code and gathering dependencies locally..."
	matlab -batch "openProject('.'); generate_cpp_code"

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

# Start the stack with the production Digital Twin binary
up-prod: .env
	@echo "COMPOSE_PROFILES=prod" >> .env
	@if [ ! -d "bld" ]; then \
		echo "Notice: 'bld/' directory not found. Pulling images from GHCR..."; \
		docker compose pull; \
		docker compose up -d --no-build; \
	else \
		docker compose up -d; \
	fi

# Start the stack with the MATLAB development environment
up-dev: .env
	@echo "COMPOSE_PROFILES=dev-env" >> .env
	docker compose up -d


down:
	docker compose --profile prod --profile dev-env down
	sudo rm -rf shared_data/

logs:
	docker compose logs -f

ps:
	docker compose ps

clean:
	docker compose down --rmi all --volumes --remove-orphans
	rm -rf bld/
