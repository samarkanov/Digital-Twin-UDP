# Makefile for managing the UDP-SSE Python services

.PHONY: build up down logs ps clean help

# Default target
default: up

help:
	@echo "Available commands:"
	@echo "  make build   - Build the Docker images"
	@echo "  make up      - Start the services in detached mode (DEFAULT)"
	@echo "  make down    - Stop and remove the services"
	@echo "  make logs    - View the logs from the services"
	@echo "  make ps      - List running services"
	@echo "  make clean   - Remove Docker images and build artifacts"
# Build everything: generate binary/libs locally, then build containers
build:
	@echo "Generating C++ code and gathering dependencies locally..."
	matlab-batch "openProject('.'); generate_cpp_code"
	docker compose build

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
