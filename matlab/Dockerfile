# Dockerfile for the Portable Digital Twin Binary
FROM ubuntu:25.04

# Install minimal runtime dependencies
# MATLAB binaries often need these for basic operation
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libasound2t64 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the portable binary and its bundled libraries
# The binary has RUNPATH=$ORIGIN/libs, so it will find them automatically
COPY bld/udp_sine_gen /app/
COPY bld/libs /app/libs
COPY config.toml /app/config.toml
COPY matlab/intercept.c /tmp/

# Compile the interceptor to remove absolute paths from dlopen calls
RUN apt-get update && apt-get install -y gcc && \
    gcc -shared -fPIC /tmp/intercept.c -o /app/libs/libintercept.so -ldl && \
    apt-get remove -y gcc && apt-get autoremove -y && \
    rm -f /tmp/intercept.c

# Ensure the binary is executable
RUN chmod +x /app/udp_sine_gen

# MATLAB runtime often creates temporary cache files
ENV MCR_CACHE_ROOT=/tmp/mcr_cache
RUN mkdir -p /tmp/mcr_cache && chmod 777 /tmp/mcr_cache

# We keep LD_LIBRARY_PATH as a safety net for any libraries 
# that might be dynamically loaded (dlopen) at runtime without being in DT_NEEDED.
ENV LD_LIBRARY_PATH=/app/libs:/app
ENV LD_PRELOAD=/app/libs/libintercept.so

# Run the binary
CMD ["./udp_sine_gen"]
