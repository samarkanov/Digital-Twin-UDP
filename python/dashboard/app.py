import os
import sqlite3
import time
import socket
import struct
from flask import Flask, render_template, jsonify, request

try:
    import tomllib
except ImportError:
    import tomli as tomllib

app = Flask(__name__)

def load_config():
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    config_path = os.path.join(base_dir, "config.toml")
    with open(config_path, "rb") as f:
        return tomllib.load(f), base_dir

def get_db_path():
    config, base_dir = load_config()
    db_rel_path = config.get("storage", {}).get("db_path", "shared_data/data.db")
    db_path = os.path.abspath(os.path.join(base_dir, db_rel_path))
    return db_path

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/data')
def get_data():
    db_path = get_db_path()
    if not os.path.exists(db_path):
        return jsonify([])

    try:
        span_mins = float(request.args.get('span', 1))
    except ValueError:
        span_mins = 1
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute('SELECT MAX(timestamp) FROM telemetry')
    latest_ts = cursor.fetchone()[0]
    
    if latest_ts is None:
        conn.close()
        return jsonify([])

    cutoff_time = latest_ts - (span_mins * 60)

    cursor.execute('''
        SELECT timestamp, value FROM telemetry 
        WHERE timestamp > ?
        ORDER BY timestamp DESC LIMIT 1000
    ''', (cutoff_time,))
    
    rows = cursor.fetchall()
    conn.close()
    rows.reverse()
    
    data = [{"timestamp": r[0], "value": r[1]} for r in rows]
    return jsonify(data)

@app.route('/api/set_pressure', methods=['POST'])
def set_pressure():
    try:
        val = float(request.json.get('value', 0))
        config, _ = load_config()
        # Use target_digital_twin for sending, fallback to '127.0.0.1'
        UDP_IP = config["network"].get("target_digital_twin", "127.0.0.1")
        UDP_PORT = config["network"]["control_port"]

        # Send via UDP to Simulink
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        data = struct.pack('<d', val)
        sock.sendto(data, (UDP_IP, UDP_PORT))
        sock.close()

        print(f"Sent set pressure: {val} to {UDP_IP}:{UDP_PORT}", flush=True)
        return jsonify({"status": "success", "value": val})
    except Exception as e:
        print(f"Error sending pressure: {e}", flush=True)
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    config, _ = load_config()
    port = config.get("dashboard", {}).get("port", 5000)
    app.run(host='0.0.0.0', port=port, debug=False)
