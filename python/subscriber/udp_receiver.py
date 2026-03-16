import socket
import json
import os
import sqlite3
from datetime import datetime

try:
    import tomllib  # Python 3.11+
except ImportError:
    import tomli as tomllib  # Fallback for older versions

def load_config():
    # Assume config.toml is two levels up from this script
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    config_path = os.path.join(base_dir, "config.toml")
    with open(config_path, "rb") as f:
        return tomllib.load(f), base_dir

def init_db(db_path):
    # Ensure the directory exists
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS telemetry (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            value REAL NOT NULL
        )
    ''')
    conn.commit()
    return conn

def main():
    config, base_dir = load_config()
    # Use bind_address for listening, fallback to 'address'
    UDP_IP = config["network"].get("bind_address", config["network"]["address"])
    UDP_PORT = config["network"]["receiver_port"]
    
    # Initialize Database
    db_rel_path = config.get("storage", {}).get("db_path", "shared_data/data.db")
    # Force absolute path resolution
    db_path = os.path.abspath(os.path.join(base_dir, db_rel_path))
    db_conn = init_db(db_path)
    db_cursor = db_conn.cursor()

    # Create a UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((UDP_IP, UDP_PORT))

    print(f"Listening for JSON UDP packets on {UDP_IP}:{UDP_PORT}...", flush=True)
    print(f"Database Absolute Path: {db_path}", flush=True)
    print(f"Database Exists: {os.path.exists(db_path)}", flush=True)

    try:
        while True:
            # Buffer size is 1024 to accommodate the JSON packet
            data, addr = sock.recvfrom(1024)
            
            try:
                # Decode and strip null bytes
                message = data.decode('utf-8').strip('\x00')
                
                # Parse JSON
                payload = json.loads(message)
                ts = payload.get('timestamp', 0)
                val = payload.get('value', 0)
                
                # Insert into Database
                db_cursor.execute('INSERT INTO telemetry (timestamp, value) VALUES (?, ?)', (ts, val))
                db_conn.commit()
                
                # Convert Unix timestamp to human-readable format for logging
                dt_obj = datetime.fromtimestamp(ts)
                readable_ts = dt_obj.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
                
                print(f"[{readable_ts}] Received & Stored: {val}", flush=True)
            except (UnicodeDecodeError, json.JSONDecodeError) as e:
                print(f"Received malformed packet ({len(data)} bytes): {data}", flush=True)
            except sqlite3.Error as e:
                print(f"Database error: {e}", flush=True)
            except Exception as e:
                print(f"Error processing packet: {e}", flush=True)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        db_conn.close()
        sock.close()

if __name__ == "__main__":
    main()
