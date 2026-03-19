---
name: digital-twin-builder
description: Builds a portable Digital Twin ecosystem using MATLAB/Simulink C++ generation, Python microservices (UDP/SSE), and Docker. Use when building hybrid digital twins with real-time monitoring and control capabilities.
---

# Digital Twin Builder

This skill provides a complete workflow for building a hybrid digital twin that integrates high-fidelity MATLAB/Simulink models with scalable Python microservices.

## Architecture

1.  **Digital Twin (MATLAB/Simulink)**: Portable C++ binary generated from Simulink using Embedded Coder. Communicates via UDP.
2.  **Publisher (Python)**: Edge data provider/controller sending UDP packets (sensor data/setpoints).
3.  **Subscriber (Python)**: Data ingestion for storage/analytics.
4.  **Dashboard (Python/Flask)**: Web UI for real-time visualization via Server-Sent Events (SSE).
5.  **DevOps**: Docker Compose for orchestration and GitHub Actions for CI/CD using "Local Build -> Release Asset" pattern.

## Workflow

### 1. Setup & Configuration
- Create project structure: `matlab/`, `python/dashboard/`, `python/publisher/`, `python/subscriber/`, `utils/`, `bld/`.
- Use `config.toml` for shared settings (IPs, ports, sample times).

### 2. MATLAB Code Generation
- Create `matlab/build_portable_binary.m` to automate the build.
- **Crucial Step**: Patch `ert_main.cpp` for an indefinite simulation loop with real-time pacing.
- **Source Patching**: Use `sed` and `perl` to replace hardcoded absolute paths and bypass `coderComputeAbsolutePath` in the generated C++ source *before* compilation.
- **Dependency Management**: Gather shared libraries into `bld/libs/`, explicitly skipping core system libs (like `libc.so`) while manually including `dlopen`'d plugins.
- See [references/matlab-patching.md](references/matlab-patching.md) for specific logic.

### 3. Python Microservices
- Implement UDP communication using `struct.pack/unpack` with **Big-Endian** format (`>d`) to match Simulink's native UDP behavior.
- Use Flask with SSE for live dashboard updates.

### 4. Containerization
- **MATLAB Dockerfile**: Use a lightweight base (e.g., Ubuntu) and inject the `bld/` directory. Use `LD_PRELOAD` for intercepting absolute library calls.
- **Python Dockerfiles**: Use `uv` for efficient dependency management and multi-stage builds.

### 5. CI/CD (GitHub Actions)
- Trigger on `release: published`.
- Download local binaries from release assets using `gh release download`.
- Build and push Docker images to **GHCR**.

## Resources
- **Patching Logic**: [references/matlab-patching.md](references/matlab-patching.md)
- **Workflow Guide**: [references/workflow.md](references/workflow.md)
- **Config Template**: [assets/config_template.toml](assets/config_template.toml)
- **Standard Makefile**: [assets/Makefile](assets/Makefile)
