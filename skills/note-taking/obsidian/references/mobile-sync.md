# Mobile Sync Options for Obsidian Vaults

## Option 1: GitHub Private Repo (Free, Recommended)

Most reliable option. Works from anywhere including behind Tor/VPN.

### Server Setup
```bash
cd /root/Documents/ObsidianVault
git init && git add -A && git commit -m "vault init"
git remote add origin git@github.com:USER/obsidian-vault.git
git push -u origin main
```

### Phone Setup
1. Install Obsidian on phone
2. Install "Obsidian Git" community plugin
3. Clone your private repo
4. Enable auto-pull on startup

## Option 2: Syncthing (Free, P2P)

⚠️ **Does NOT work if server is behind Tor** — Tor blocks incoming connections needed for P2P sync. Only use if server has direct internet access.

## Option 3: Obsidian Sync (Paid, $4/month)
- Official end-to-end encrypted sync
- Simplest setup — just login on both devices

## Option 4: Direct Download (Quick)
```bash
cd /root/Documents
tar czf /tmp/HermesVault.tar.gz ObsidianVault/
# Transfer via any method
```

### Server Setup
```bash
# Install
curl -sL https://github.com/syncthing/syncthing/releases/download/v1.27.12/syncthing-linux-arm64-v1.27.12.tar.gz | tar xz -C /usr/local/bin --strip-components=1

# Generate config
syncthing generate --home=/root/.config/syncthing

# Start (background)
syncthing serve --home=/root/.config/syncthing --no-browser &

# Get device ID
syncthing -device-id
```

### Add Vault Folder to Config
```python
import xml.etree.ElementTree as ET
tree = ET.parse('/root/.config/syncthing/config.xml')
root = tree.getroot()
folder = ET.SubElement(root, 'folder')
folder.set('id', 'obsidian-vault')
folder.set('label', 'Hermes-Vault')
folder.set('path', '/root/Documents/ObsidianVault')
folder.set('type', 'sendonly')
folder.set('fsWatcherEnabled', 'true')
tree.write('/root/.config/syncthing/config.xml')
```

### Phone Setup
1. Install Syncthing from F-Droid or Play Store
2. Add server device using Device ID
3. Accept folder share
4. Open vault in Obsidian app

## Option 2: Obsidian Sync (Paid, $4/month)
- Official end-to-end encrypted sync
- Simplest setup — just login on both devices
- Requires Obsidian account

## Option 3: GitHub Private Repo (Free)
```bash
cd /root/Documents/ObsidianVault
git init && git add -A && git commit -m "vault init"
git remote add origin git@github.com:USER/obsidian-vault.git
git push -u origin main
```
Phone: Use Obsidian Git plugin to pull changes.

## Option 4: Google Drive / Dropbox (Free, Manual)
- Upload vault folder to cloud storage
- Open from cloud storage in Obsidian app
- Not real-time, requires manual sync
