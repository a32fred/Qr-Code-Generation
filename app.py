#!/usr/bin/env python3
import os
import sqlite3
import json
import uuid
import base64
from datetime import datetime, timedelta
from flask import Flask, request, jsonify, send_file
import qrcode
from io import BytesIO

app = Flask(__name__)

# Config
DB_FILE = 'data/qrapi.db'
PLANS = {"free": 100, "starter": 2500, "pro": 10000, "business": 100000}

# Initialize DB
def init_db():
    os.makedirs('data', exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    conn.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY,
            api_key TEXT UNIQUE,
            plan TEXT DEFAULT 'free',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.execute('''
        CREATE TABLE IF NOT EXISTS qr_codes (
            id TEXT PRIMARY KEY,
            user_id INTEGER,
            data TEXT,
            scans INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

@app.route('/')
def home():
    return jsonify({
        "service": "QR Code API",
        "version": "1.0",
        "docs": "https://qrapi.dev/docs",
        "pricing": {
            "free": "100 QRs/month",
            "starter": "$5/month - 2,500 QRs",
            "pro": "$15/month - 10,000 QRs + features",
            "business": "$50/month - 100,000 QRs + everything"
        }
    })

@app.route('/api/register', methods=['POST'])
def register():
    api_key = f"qr_{uuid.uuid4().hex}"
    
    conn = sqlite3.connect(DB_FILE)
    try:
        conn.execute("INSERT INTO users (api_key) VALUES (?)", (api_key,))
        conn.commit()
        return jsonify({
            "api_key": api_key,
            "plan": "free",
            "limit": 100,
            "message": "Welcome! You have 100 free QR codes per month."
        })
    except:
        return jsonify({"error": "Failed to create user"}), 500
    finally:
        conn.close()

@app.route('/api/generate', methods=['POST'])
def generate():
    api_key = request.headers.get('X-API-Key')
    if not api_key:
        return jsonify({"error": "API key required"}), 401
    
    # Get user
    conn = sqlite3.connect(DB_FILE)
    user = conn.execute("SELECT id, plan FROM users WHERE api_key = ?", (api_key,)).fetchone()
    if not user:
        conn.close()
        return jsonify({"error": "Invalid API key"}), 401
    
    user_id, plan = user
    
    # Check usage (simple monthly count)
    month = datetime.now().strftime('%Y-%m')
    usage = conn.execute(
        "SELECT COUNT(*) FROM qr_codes WHERE user_id = ? AND strftime('%Y-%m', created_at) = ?",
        (user_id, month)
    ).fetchone()[0]
    
    limit = PLANS[plan]
    if usage >= limit:
        conn.close()
        return jsonify({"error": "Monthly limit exceeded", "usage": usage, "limit": limit}), 429
    
    # Generate QR
    data = request.json
    qr_data = data.get('data', '')
    size = data.get('size', 256)
    
    if not qr_data:
        conn.close()
        return jsonify({"error": "Data field required"}), 400
    
    # Create QR code
    qr = qrcode.QRCode(version=1, box_size=size//25, border=4)
    qr.add_data(qr_data)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    # Convert to base64
    buffered = BytesIO()
    img.save(buffered, format="PNG")
    img_base64 = base64.b64encode(buffered.getvalue()).decode()
    
    # Save to DB
    qr_id = uuid.uuid4().hex[:16]
    conn.execute("INSERT INTO qr_codes (id, user_id, data) VALUES (?, ?, ?)", 
                (qr_id, user_id, qr_data))
    conn.commit()
    conn.close()
    
    base_url = os.getenv('BASE_URL', 'http://localhost:5000')
    
    return jsonify({
        "qr_code": img_base64,
        "qr_url": f"{base_url}/qr/{qr_id}",
        "analytics": f"{base_url}/analytics/{qr_id}"
    })

@app.route('/api/usage')
def usage():
    api_key = request.headers.get('X-API-Key')
    if not api_key:
        return jsonify({"error": "API key required"}), 401
    
    conn = sqlite3.connect(DB_FILE)
    user = conn.execute("SELECT id, plan FROM users WHERE api_key = ?", (api_key,)).fetchone()
    if not user:
        conn.close()
        return jsonify({"error": "Invalid API key"}), 401
    
    user_id, plan = user
    month = datetime.now().strftime('%Y-%m')
    usage_count = conn.execute(
        "SELECT COUNT(*) FROM qr_codes WHERE user_id = ? AND strftime('%Y-%m', created_at) = ?",
        (user_id, month)
    ).fetchone()[0]
    
    limit = PLANS[plan]
    conn.close()
    
    return jsonify({
        "plan": plan,
        "usage": usage_count,
        "limit": limit,
        "remaining": limit - usage_count
    })

@app.route('/qr/<qr_id>')
def view_qr(qr_id):
    conn = sqlite3.connect(DB_FILE)
    qr_data = conn.execute("SELECT data FROM qr_codes WHERE id = ?", (qr_id,)).fetchone()
    if not qr_data:
        conn.close()
        return jsonify({"error": "QR code not found"}), 404
    
    # Increment scan
    conn.execute("UPDATE qr_codes SET scans = scans + 1 WHERE id = ?", (qr_id,))
    conn.commit()
    conn.close()
    
    data = qr_data[0]
    if data.startswith('http'):
        return f'<script>window.location.href="{data}"</script>'
    else:
        return jsonify({"data": data})

@app.route('/analytics/<qr_id>')
def analytics(qr_id):
    conn = sqlite3.connect(DB_FILE)
    result = conn.execute("SELECT scans, created_at FROM qr_codes WHERE id = ?", (qr_id,)).fetchone()
    if not result:
        conn.close()
        return jsonify({"error": "QR code not found"}), 404
    
    scans, created_at = result
    conn.close()
    
    return jsonify({
        "qr_id": qr_id,
        "total_scans": scans,
        "created_at": created_at
    })

if __name__ == '__main__':
    init_db()
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=True)