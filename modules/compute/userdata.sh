#!/bin/bash
# ============================================================
# userdata.sh — runs once when EC2 instance first boots
# Option A: Direct Node.js on EC2 (no Docker)
# Steps:
#   1. Install Node.js 20
#   2. Fetch DB password from Secrets Manager
#   3. Write environment file
#   4. Copy app code
#   5. Start app as systemd service
# ============================================================
set -euxo pipefail

# ── 1. System updates and Node.js install ────────────────────
yum update -y
yum install -y jq aws-cli

# Install Node.js 20 via NodeSource
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs

# ── 2. Fetch DB password from Secrets Manager ────────────────
# EC2 IAM role has permission to read this specific secret
# Password is never stored in plaintext anywhere
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')

# ── 3. Write environment file ────────────────────────────────
# Readable only by root — app runs as nobody user
cat > /etc/app.env <<EOF
PORT=${app_port}
NODE_ENV=production
DB_HOST=${db_host}
DB_PORT=5432
DB_NAME=${db_name}
DB_USER=${db_username}
DB_PASSWORD=$DB_PASSWORD
EOF
chmod 600 /etc/app.env

# ── 4. Copy app code ─────────────────────────────────────────
# In production replace this block with your actual deploy step:
# Option 1: aws s3 cp s3://your-bucket/app.tar.gz /opt/app.tar.gz
# Option 2: git clone your repo
# Option 3: CodeDeploy agent
mkdir -p /opt/app

cat > /opt/app/package.json <<'EOF'
{
  "name": "taskflow-api",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3",
    "cors": "^2.8.5"
  }
}
EOF

cat > /opt/app/index.js <<'EOF'
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app  = express();
const port = process.env.PORT || 4000;

app.use(cors());
app.use(express.json());

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     parseInt(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl:      { rejectUnauthorized: false },
});

// Health check — ALB pings this every 30 seconds
// Returns 200 only if DB connection is also healthy
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'connected', env: process.env.NODE_ENV });
  } catch (err) {
    res.status(503).json({ status: 'error', db: 'disconnected' });
  }
});

// Tasks routes
app.get('/api/tasks', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT * FROM tasks ORDER BY created_at DESC'
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/tasks', async (req, res) => {
  try {
    const { title, description = '', status = 'todo', priority = 'medium' } = req.body;
    if (!title) return res.status(400).json({ error: 'Title is required' });
    const { rows } = await pool.query(
      'INSERT INTO tasks (title, description, status, priority) VALUES ($1,$2,$3,$4) RETURNING *',
      [title, description, status, priority]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/api/tasks/:id', async (req, res) => {
  try {
    const fields = ['title', 'description', 'status', 'priority'];
    const updates = [];
    const values  = [];
    let idx = 1;
    for (const f of fields) {
      if (req.body[f] !== undefined) {
        updates.push(`${f} = $${idx++}`);
        values.push(req.body[f]);
      }
    }
    if (!updates.length) return res.status(400).json({ error: 'No fields to update' });
    values.push(req.params.id);
    const { rows } = await pool.query(
      `UPDATE tasks SET ${updates.join(', ')} WHERE id = $${idx} RETURNING *`,
      values
    );
    if (!rows.length) return res.status(404).json({ error: 'Not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/tasks/:id', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'DELETE FROM tasks WHERE id = $1 RETURNING id', [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Not found' });
    res.json({ deleted: rows[0].id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(port, () => {
  console.log(`TaskFlow API running on port ${port}`);
});
EOF

# Install dependencies
cd /opt/app && npm install --production

# ── 5. Systemd service — keeps app running forever ───────────
cat > /etc/systemd/system/app.service <<EOF
[Unit]
Description=TaskFlow Node.js API
After=network.target

[Service]
EnvironmentFile=/etc/app.env
ExecStart=/usr/bin/node /opt/app/index.js
Restart=always
RestartSec=5
User=nobody
WorkingDirectory=/opt/app
StandardOutput=journal
StandardError=journal
SyslogIdentifier=taskflow

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable app
systemctl start app

echo "TaskFlow API started successfully"