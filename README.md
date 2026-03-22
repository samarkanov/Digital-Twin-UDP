# Digital Twin with Simulink, Simulink Coder 

This project implements a portable Digital Twin (implemented in Simulink) that communicates over UDP with a Python-based components. It features a live data publisher, a subscriber, a digital twin, and a web dashboard for visualization. The application is deployed as a Docker composition and includes a specialized agentic skill, `digital-twin-builder`, to assist in extending or rebuilding the ecosystem.

![](./static/simulink-udp-arch.svg)

![](./static/main-rec.gif)

![](./static/simulink-model.png)

## Agentic Skill: Digital Twin Builder

This project includes a built-in Gemini CLI skill designed to assist with the entire lifecycle of building, patching, and maintaining a hybrid digital twin ecosystem.

To activate the skill within Gemini CLI:
```bash
/skill activate digital-twin-builder
```

### Prompting the Skill

You can use the following prompt as a starting point to rebuild or extend the ecosystem:

> "I want to build a real-time Digital Twin from scratch. Please use the digital-twin-builder skill to guide the process. The project should include a MATLAB/Simulink model that generates a portable C++ binary, Python microservices for publishing/subscribing via UDP, and a Flask dashboard with Server-Sent Events. Set up Docker Compose and a GitHub Actions workflow for a 'Local Build -> Release Asset' deployment strategy."

The skill provides expert guidance and automated workflows for:
- **MATLAB/Simulink**: Automated code generation, source-level path patching, and dependency gathering.
- **Python Microservices**: Implementation of UDP communication with proper endianness (`>d`) and SSE-based dashboards.
- **Containerization**: Specialized Docker patterns for portable MATLAB binaries and lightweight Python services.
- **CI/CD**: Workflows for the "Local Build -> GitHub Release -> GHCR" deployment pattern.

## Architecture

- **Digital Twin (MATLAB/Simulink)**: A compiled C++ binary generated in Simulink (with Simulink Coder) that simulates a sine wave generator with UDP input/output blocks.
- **Publisher (Python)**: Sends input values to the Digital Twin Simulink model via UDP.
- **Subscriber (Python)**: Receives the processed signal from the Digital Twin.
- **Dashboard (Python/Flask)**: Visualizes the real-time data flow.

## Prerequisites

- Docker & Docker Compose to build the application
- (Optional) MATLAB, Simulink to open Simulink model
- (Optional) Instrument Control Toolbox to communicate over UDP
- (Optional) Simulink Coder, Embedded Coder to build a binary

## Getting Started

```bash
# Start the services (automatically pulls images from GitHub)
make up-prod
```

The dashboard will be available at `http://localhost:5000`.

![](./static/recording-4.gif)

### Developer Setup

#### Build and Starting Development Stack
```bash
make up-dev
```
Then, open your browser and navigate to `http://localhost:8888/`. This will open MATLAB using online licensing by default. Once signed in, a MATLAB session will start, and you will be ready to develop your code.

If you wish to use a local license file or a license server instead of online licensing, provide a value for `matlab_license_file` in [config.toml](./config.toml).

The MATLAB environment comes with all necessary toolboxes for this project pre-installed and ready to use.

![](./static/mos.png)

#### Opening the Simulink model

```matlab
>> cd project;
>> openProject('.');
>> open_system('udp_sine_gen');
```

#### Starting the Simulink model
As part of the development stack, the UDP infrastructure is up and running; there are senders that publish data and a subscriber that listens for incoming data. You can start the Simulink model and open the dashboard to see the data flow live.

![](./static/start-model.gif)


#### Generating C++ code and building the portable binary
```matlab
>> openProject('.');
>> generate_cpp_code
```

#### Generating Simulink model from scratch
You can regenerate the Simulink model with MATLAB script:

```matlab
>> openProject('.');
>> create_udp_simulink_model
```

## Makefile Commands

| Command | Description |
| :--- | :--- |
| `make up-prod` | Start full stack including production Digital Twin binary (default). |
| `make up-dev` | Start stack with MATLAB interactive development container. |
| `make down` | Stop services and cleanup. |
| `make logs` | Follow Docker Compose logs. |
| `make ps` | List running services and their status. |
| `make release TAG=v1.0.x` | Build, zip, and create a GitHub Release. |
| `make build` | Build the MATLAB binary and gather dependencies. |
| `make clean` | Remove Docker images and build artifacts. |

