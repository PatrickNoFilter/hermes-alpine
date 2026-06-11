# hermes-alpine

Full Hermes Agent ecosystem — hermes-agent code, skills, plugins, and runtime scripts — packaged for migration from Ubuntu to Alpine Linux.

## What's included

```
hermes-alpine/
├── hermes-agent/    # Main agent codebase (from ~/hermes-webui/)
├── skills/           # All custom skills (~60+)
├── plugins/          # hermes-lcm, rtk-rewrite
├── scripts/          # Runtime helper scripts
├── config.yaml.example  # Sanitized config template
└── .gitignore        # Excludes all runtime & credential files
```

## Setup on Alpine

```bash
# 1. Install deps
apk add python3 py3-pip git nodejs npm

# 2. Clone
git clone https://github.com/PatrickNoFilter/hermes-alpine.git ~/hermes-alpine
cd ~/hermes-alpine

# 3. Copy and edit config
cp config.yaml.example ~/.hermes/config.yaml
nano ~/.hermes/config.yaml   # fill in your API keys

# 4. Install Python deps
pip install -r hermes-agent/requirements.txt

# 5. Bootstrap
cd hermes-agent
python3 bootstrap.py
```

## Key notes

- **Never commit `config.yaml`, `.env`, or any file with live credentials** — all are excluded via `.gitignore`
- **Runtime directories** (`sessions/`, `memories/`, `cache/`, `logs/`, `state.db`, `auth.json`) are excluded — recreate fresh on the new machine
- **Alpine-specific**: Use `apk` instead of `apt`. Python `venv` preferred over `.venv` auto-detection. See `scripts/post-update-termux.sh` for Alpine-specific pip fixes.

## Skills structure

Each skill lives in `skills/<skill-name>/SKILL.md`. Load with:
```
/skill <skill-name>
```