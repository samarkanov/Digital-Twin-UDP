# Digital Twin Builder Workflow

This guide details the sequential workflow for developing, containerizing, and deploying a hybrid digital twin.

## 1. Project Initialization
- Initialize a new project directory.
- Create subdirectories: `matlab/`, `python/dashboard/`, `python/publisher/`, `python/subscriber/`, `utils/`, `bld/`.
- Add `config.toml` to the project root for shared configuration.

## 2. MATLAB Implementation
- Design the Simulink model with **UDP Send/Receive** blocks.
- **Note on Endianness**: Simulink UDP blocks default to **Big-Endian**. Python services must use `struct.pack('>d', val)` and `struct.unpack('>d', data)`.
- Configure **Embedded Coder** for fixed-step, discrete simulation.
- Write `matlab/build_portable_binary.m` for automated code generation and source-level patching.

## 3. Python Microservices
- Implement **UDP Publisher** to stream sensor/control data using Big-Endian format.
- Implement **UDP Subscriber** to capture and persist twin output.
- Build the **Dashboard** using Flask and Server-Sent Events (SSE) for real-time UI updates.

## 4. Docker Orchestration
- **MATLAB Dockerfile**:
    - Use `RUN chmod +x /app/digital-twin` to ensure execution.
    - Set `ENV LD_PRELOAD=/app/libs/libintercept.so` to handle dynamic loading.
    - Bundle `libstdc++.so.6` from the host if it's more recent than MATLAB's internal version.
- **Python Dockerfiles**: Use multi-stage builds or lightweight bases (e.g., `python:3.11-slim`).

## 5. Deployment Strategy (Local Build -> GitHub Release)
- **Local Build**: Generate the binary on a machine with a valid MATLAB license.
- **GitHub Release**: Create a release and upload the `bld/` directory as a zip asset (`bld.zip`).
- **GitHub Action**:
    - Trigger on `release: published`.
    - Download the release asset using `gh release download`.
    - Build and push Docker images to **GHCR**.

## 6. Verification
- Use `make build` for local development.
- Use `make release TAG=vX.Y.Z` for production builds.
- Use `make up` to pull images from GHCR and start the ecosystem.
- Monitor logs: `docker compose logs -f`.
