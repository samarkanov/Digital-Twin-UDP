import socket
import struct
import time
import math
import os

try:
    import tomllib  # Python 3.11+
except ImportError:
    import tomli as tomllib  # Fallback for older versions

def load_config():
    # Assume config.toml is two levels up from this script
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    config_path = os.path.join(base_dir, "config.toml")
    with open(config_path, "rb") as f:
        return tomllib.load(f)

def main():
    config = load_config()
    
    # Use target_digital_twin for sending, fallback to '127.0.0.1'
    UDP_IP = config["network"].get("target_digital_twin", "127.0.0.1")
    UDP_PORT = config["network"]["sink_port"]
    
    # Use bind_address for local binding
    BIND_IP = config["network"].get("bind_address", "0.0.0.0")
    BIND_PORT = config["network"].get("publisher_port", 0)
    
    SAMPLE_TIME = config["simulation"]["sample_time"]
    FREQUENCY = 1.0 / SAMPLE_TIME

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # Bind to specified address and port
    try:
        sock.bind((BIND_IP, BIND_PORT))
        print(f"Publisher bound locally to {BIND_IP}:{BIND_PORT}", flush=True)
    except socket.error as e:
        print(f"Warning: Could not bind to {BIND_IP}:{BIND_PORT}: {e}", flush=True)

    print(f"Publishing offset data to {UDP_IP}:{UDP_PORT} (Sample Time: {SAMPLE_TIME}s, Frequency: {FREQUENCY:.1f}Hz)...", flush=True)
    print("Press Ctrl+C to stop.", flush=True)

    start_time = time.time()
    
    try:
        while True:
            # Generate a dynamic offset (e.g., a slow sine wave between 2.0 and 3.0)
            elapsed = time.time() - start_time
            offset = 2.5 + 0.5 * math.sin(elapsed * 0.5)
            
            # Pack as little-endian double
            data = struct.pack('<d', offset)
            sock.sendto(data, (UDP_IP, UDP_PORT))
            
            # Match simulation sample time
            time.sleep(SAMPLE_TIME)
            
    except KeyboardInterrupt:
        print("\nStopping publisher...")
    finally:
        sock.close()

if __name__ == "__main__":
    main()
