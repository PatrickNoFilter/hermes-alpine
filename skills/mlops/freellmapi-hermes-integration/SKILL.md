---
name: freellmapi-hermes-integration
description: Integrate FreeLLMAPI as an external OpenAI-compatible provider for Hermes Agent on Termux/PRoot ARM64
version: "1.0"
---

# FreeLLMAPI ↔ Hermes Integration

Integrates [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi) — a self-hosted
LLM proxy that aggregates 16+ free-tier provider APIs into a single OpenAI-compatible
endpoint with smart routing, per-key rate tracking, and automatic failover — as an
external provider for Hermes Agent.

## Prerequisites
- Node.js v20+ (v22 confirmed working on ARM64)
- Hermes Agent installed
- FreeLLMAPI repo cloned: `git clone --depth=1 https://github.com/tashfeenahmed/freellmapi.git ~/freellmapi`

## Setup

### 1. Install dependencies
```bash
cd ~/freellmapi && npm install
```

### 2. Rebuild native bindings (ARM64)
```bash
cd ~/freellmapi && npm rebuild better-sqlite3
```

### 3. Create .env
```bash
cd ~/freellmapi
ENCRYPTION_KEY="$(node -e 'console.log(require("crypto").randomBytes(32).toString("hex"))')"
cat > .env <<EOF
ENCRYPTION_KEY=$ENCRYPTION_KEY
PORT=3001
HOST_BIND=127.0.0.1
EOF
```

### 4. Start server
```bash
cd ~/freellmapi/server && npx tsx src/index.ts
```

Use background mode for Hermes:
```bash
cd ~/freellmapi/server && nohup npx tsx src/index.ts > /tmp/freellmapi.log 2>&1 &
```

Or via Hermes script:
```bash
bash ~/.hermes/scripts/freellmapi-start.sh
```

### 5. Create admin account
```bash
curl -s -X POST http://localhost:3001/api/auth/setup \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@freellmapi.local","password":"your-password-here"}'
```

### 6. Get unified API key
```bash
# Login
TOKEN=$(curl -s -X POST http://localhost:3001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@freellmapi.local","password":"your-password-here"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")

# Get unified API key
curl -s http://localhost:3001/api/settings/api-key \
  -H "Authorization: Bearer $TOKEN"
```

### 7. Add provider keys
```bash
# See available platforms in keys.ts: google, groq, cerebras, etc.
TOKEN="..." # from login

curl -s -X POST http://localhost:3001/api/keys \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"platform":"google","key":"your-gemini-api-key"}'
```

### 8. Configure Hermes
```bash
hermes config set providers.custom_freellmapi.base_url http://localhost:3001/v1
hermes config set providers.custom_freellmapi.api_key env://FREELLMAPI_KEY

# Add FREELLMAPI_KEY=your-key to ~/.hermes/.env
echo "FREELLMAPI_KEY=your-key-here" >> ~/.hermes/.env
```

### 9. Switch Hermes to use FreeLLMAPI
```bash
hermes config set model.provider custom_freellmapi
hermes config set model.default auto
```

## API Endpoints (Dashboardless)

Since the React dashboard build may fail on ARM64, use curl/Python:

| Endpoint | Method | Description |
|---|---|---|
| `/api/auth/login` | POST | Login, returns token |
| `/api/auth/status` | GET | Check setup + auth status |
| `/api/keys` | GET | List provider keys (masked) |
| `/api/keys` | POST | Add a provider key |
| `/api/keys/custom` | POST | Add custom OpenAI-compatible endpoint |
| `/api/keys/:id` | DELETE | Remove a key |
| `/api/settings/api-key` | GET | Get unified API key |
| `/api/settings/api-key/regenerate` | POST | Regenerate unified key |
| `/api/models` | GET | List all models from added providers |
| `/api/ping` | GET | Health check (no auth) |

## Pitfalls

- **better-sqlite3 native addon**: Will fail on ARM64 with "Could not locate bindings file" unless you run `npm rebuild better-sqlite3`
- **TypeScript build fails on ARM64**: The `npm run build` step fails with missing `@types/express`. Use `npx tsx src/index.ts` (dev mode) instead — it transpiles on the fly and ignores type errors
- **Dashboard (React SPA) not built**: The client build also fails. All admin operations work via the REST API — no dashboard needed
- **Server process persistence**: The `tsx` dev server is not a daemon. Use nohup, tmux, or Hermes `cronjob` for persistence
- **No Docker on Termux**: Direct Node.js deployment required

## Verification

### 1. Repository health (is it maintained?)
```bash
curl -s https://api.github.com/repos/tashfeenahmed/freellmapi | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'Stars: {d[\"stargazers_count\"]}')
print(f'Forks: {d[\"forks_count\"]}')
print(f'Open issues: {d[\"open_issues_count\"]}')
print(f'Last push: {d[\"pushed_at\"][:10]}')
print(f'CI: {\"✅\" if d.get(\"default_branch\") else \"❓\"} — check Actions tab')
print(f'License: {d[\"license\"][\"name\"] if d.get(\"license\") else \"N/A\"}')
"
```

### 2. Check if server is running
```bash
curl -s --connect-timeout 3 http://localhost:3001/api/ping && echo " ✅ alive"
# No response = server not running
```

### 3. Full diagnosis — filesystem, process, port, DB
```bash
# A) Is the repo cloned?
ls -d ~/freellmapi 2>/dev/null && echo " ✅ repo exists" || echo " ❌ repo missing"

# B) Are node_modules installed?
ls -d ~/freellmapi/node_modules 2>/dev/null && echo " ✅ node_modules" || echo " ❌ npm install needed"

# C) Is the server process running?
ps aux | grep -i "tsx src/index" | grep -v grep && echo " ✅ process" || echo " ❌ not running — start it"

# D) Is the port open?
ss -tlnp | grep 3001 && echo " ✅ port 3001" || echo " ❌ port closed"

# E) Is the .env configured?
cat ~/freellmapi/.env 2>/dev/null || echo " ❌ .env missing"
```

### 4. Database inspection — check key health
```bash
cd ~/freellmapi/server
python3 -c "
import sqlite3, sys
conn = sqlite3.connect('data/freeapi.db')
cur = conn.cursor()
cur.execute('SELECT platform, status, enabled FROM api_keys')
rows = cur.fetchall()
print(f'API keys ({len(rows)}):')
for p, s, e in rows:
    icon = {'healthy':'✅','disabled':'⚠️','error':'❌'}.get(s,'❓')
    print(f'  {icon} {p}: {s} (enabled={bool(e)})')
cur.execute('SELECT COUNT(*) FROM models')
print(f'Models: {cur.fetchone()[0]}')
cur.execute('SELECT COUNT(*) FROM users')
print(f'Users: {cur.fetchone()[0]}')
conn.close()
"
```

### 5. Test the API
```bash
# List models
curl -s http://localhost:3001/v1/models \
  -H "Authorization: Bearer $(grep FREELLMAPI_KEY ~/.hermes/.env | cut -d= -f2)" | python3 -c "
import json,sys; d=json.load(sys.stdin); print(f'{len(d.get(\"data\",[]))} models')
"

# Chat completion — verify routing works
curl -s http://localhost:3001/v1/chat/completions \
  -H "Authorization: Bearer $(grep FREELLMAPI_KEY ~/.hermes/.env | cut -d= -f2)" \
  -H "Content-Type: application/json" \
  -d '{"model":"auto","messages":[{"role":"user","content":"Say just hello in one word"}],"max_tokens":20}' \
  | python3 -c "
import json,sys
r = json.load(sys.stdin)
m = r['choices'][0]['message']['content']
p = r.get('_routed_via',{}).get('platform','?')
md = r.get('model','?')
print(f'✅ Reply: \"{m}\" via {p}/{md}')
print(f'   Tokens: {r[\"usage\"][\"prompt_tokens\"]} in / {r[\"usage\"][\"completion_tokens\"]} out')
"
```

### 6. Start server if down
```bash
cd ~/freellmapi/server && nohup npx tsx src/index.ts > /tmp/freellmapi.log 2>&1 &
sleep 5 && curl -s http://localhost:3001/api/ping
```
