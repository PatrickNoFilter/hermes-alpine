---
name: onex
description: "Security/pentesting tool installer — search, install, and manage 860+ hacking tools (nmap, sqlmap, john, hydra, metasploit, etc.) from onex + hackingtool + WebHackersWeapons repos. Use when asked to install security tools, pentest tools, Kali tools, or hacking tools."
version: "3.0.0"
---

# Unified Security Tools — 860+ Tools

866+ security/pentesting tools from three repos, merged & deduplicated.

- **[onex](https://github.com/jackind424/onex)** — 370 tools (Shell-based installer)
- **[hackingtool](https://github.com/Z4nzu/hackingtool)** — 185 tools (Python menu, 76k⭐)
- **[WebHackersWeapons](https://github.com/hahwul/WebHackersWeapons)** — 429 tools (Web-focused, 4.6k⭐)
- **Top GitHub Stars** — 6 additional tools (10k-33k⭐ each)

**⚠️ AUTHORIZED USE ONLY — Only install tools you are authorized to use.**

## Setup

```bash
# Option A: onex
git clone https://github.com/jackind424/onex.git && sh onex/install

# Option B: hackingtool
git clone https://github.com/Z4nzu/hackingtool.git && sudo ./hackingtool/install.sh
```

## CLI Usage

```bash
onex search <tool>       # Search
onex install <tool>      # Install
onex list -a             # List all
```

## 🏆 Top Tools by GitHub Stars

| Tool | Stars | Description |
|------|-------|-------------|
| [metasploit-framework](https://github.com/rapid7/metasploit-framework) | 38,269 | Penetration testing framework |
| [sqlmap](https://github.com/sqlmapproject/sqlmap) | 37,508 | SQL injection & database takeover |
| [web-check](https://github.com/lissy93/web-check) | 33,246 | All-in-one OSINT website analyzer |
| [nuclei](https://github.com/projectdiscovery/nuclei) | 28,943 | Fast vulnerability scanner |
| [mimikatz](https://github.com/gentilkiwi/mimikatz) | 21,590 | Windows credential extraction |
| [spiderfoot](https://github.com/smicallef/spiderfoot) | 17,984 | OSINT automation |
| [katana](https://github.com/projectdiscovery/katana) | 16,875 | Web crawler/spider |
| [ffuf](https://github.com/ffuf/ffuf) | 16,157 | Fast web fuzzer |
| [lynis](https://github.com/CISOfy/lynis) | 15,701 | Security auditing |
| [zaproxy](https://github.com/zaproxy/zaproxy) | 15,200 | Web app security scanner |
| [nmap](https://github.com/nmap/nmap) | 12,966 | Network mapper |
| [thc-hydra](https://github.com/vanhauser-thc/thc-hydra) | 11,837 | Password cracker |
| [sliver](https://github.com/BishopFox/sliver) | 11,277 | Adversary emulation/C2 |
| [BloodHound](https://github.com/BloodHoundAD/BloodHound) | 10,541 | Active Directory attack paths |

## Tool Categories (866 tools)

| Category | Count | Examples |
|----------|-------|----------|
| ⚔️ Army-Knife | 7 | ZAP, Metasploit, BurpSuite |
| 🔍 Information Gathering | 55+ | nmap, recon-ng, Amass |
| 🔍 Recon | 120+ | subfinder, katana, httpx |
| 🔎 Scanner | 95+ | nuclei, nikto, trivy |
| 🌐 Web Attack | 40+ | sqlmap, WPScan, commix |
| 🧰 Fuzzer | 27+ | ffuf, wfuzz, feroxbuster |
| 💥 Exploitation | 16+ | metasploit, sqlninja |
| 🔑 Password Attacks | 15+ | john, hashcat, Hydra |
| 🎣 Phishing | 17+ | SocialFish, HiddenEye |
| 📶 Wireless | 15+ | aircrack-ng, Wifite2 |
| 🔬 Forensics | 18+ | Autopsy, Binwalk |
| 🛠 Utils | 149+ | curl, httpie, gron |

Full catalog: `references/tool-catalog.md`

## Full Reinstall

```bash
bash /root/workspace/hermes-reinstall.sh
```

Reinstalls everything from scratch: system packages, Python venv, DeepLX, GitHub repos, skills, OPSEC, shell hooks.

Source list: `/root/workspace/hermes-sources.md`

## Pitfalls

- Some tools require specific dependencies (python3, golang, ruby, perl, php)
- hackingtool requires Python 3.10+
- Some tools may only work on Kali/Parrot
- Always use in authorized, isolated environments
- The catalog shows which source each tool came from (1=onex, 2=hackingtool, 3=WebHackersWeapons, ⭐=2 sources, 🌟=all 3)
- Top starred tools (10k-38k⭐) were added from GitHub search: metasploit, sqlmap, web-check, nuclei, mimikatz, katana, ffuf, nmap, hydra, sliver, BloodHound

## Multi-Source Merge Methodology

When combining tool catalogs from multiple repos:

1. **Dedup by URL** — most reliable key (tool names vary, URLs are stable)
2. **Keep the richer entry** — prefer entries with repo URLs, descriptions, categories
3. **Track sources** — mark which repo each tool came from (1=onex, 2=hackingtool, 3=WebHackersWeapons, ⭐=2 sources, 🌟=all 3)
4. **Normalize categories** — different repos use different category names (e.g., "information_gathering" vs "Information Gathering" vs "Recon")
5. **Build unified catalog** — single sorted table with source attribution

### Merge Pattern
```python
all_tools = {}
for t in source_a + source_b + source_c:
    key = t['url'].lower().rstrip('/')
    if key not in all_tools:
        all_tools[key] = t
    else:
        all_tools[key]['source'] = 'both'
```

### Sources Used
| Repo | Tools | Stars |
|------|-------|-------|
| onex | 370 | 848 |
| hackingtool | 185 | 76,650 |
| WebHackersWeapons | 429 | 4,611 |
| Top GitHub Stars | 6 additional | 10k-33k each |
