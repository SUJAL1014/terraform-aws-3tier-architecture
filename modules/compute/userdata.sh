#!/bin/bash
# ============================================================
# userdata.sh — pure bash, no Terraform template syntax
# All config comes from /etc/app-config.env written by main.tf
# ============================================================
set -euxo pipefail

# ── 1. Install dependencies ───────────────────────────────────
yum update -y
yum install -y jq aws-cli
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs

# ── 2. Load config written by Terraform ──────────────────────
source /etc/app-config.env

# ── 3. Fetch DB password from Secrets Manager ────────────────
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$DB_SECRET_ARN" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)

DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')

# ── 4. Write app environment file ────────────────────────────
cat > /etc/app.env <<EOF
PORT=$APP_PORT
NODE_ENV=production
DB_HOST=$DB_HOST
DB_PORT=5432
DB_NAME=$DB_NAME
DB_USER=$DB_USERNAME
DB_PASSWORD=$DB_PASSWORD
EOF
chmod 600 /etc/app.env

# ── 5. Write app code ────────────────────────────────────────
mkdir -p /opt/app

cat > /opt/app/package.json <<EOF
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
const cors    = require('cors');

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

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'connected' });
  } catch (err) {
    res.status(503).json({ status: 'error', db: 'disconnected' });
  }
});

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
    if (!title) return res.status(400).json({ error: 'Title required' });
    const { rows } = await pool.query(
      'INSERT INTO tasks (title,description,status,priority) VALUES ($1,$2,$3,$4) RETURNING *',
      [title, description, status, priority]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/api/tasks/:id', async (req, res) => {
  try {
    const fields  = ['title','description','status','priority'];
    const updates = [];
    const values  = [];
    let idx = 1;
    for (const f of fields) {
      if (req.body[f] !== undefined) {
        updates.push(f + ' = $' + idx++);
        values.push(req.body[f]);
      }
    }
    if (!updates.length) return res.status(400).json({ error: 'No fields' });
    values.push(req.params.id);
    const { rows } = await pool.query(
      'UPDATE tasks SET ' + updates.join(', ') + ' WHERE id = $' + idx + ' RETURNING *',
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
      'DELETE FROM tasks WHERE id = $1 RETURNING id',
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Not found' });
    res.json({ deleted: rows[0].id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(port, () => console.log('TaskFlow API on port ' + port));
EOF

cd /opt/app && npm install --production

# ── 6. Systemd service ────────────────────────────────────────
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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable app
systemctl start app

echo "TaskFlow API started"