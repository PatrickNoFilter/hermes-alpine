# Security Ecosystem Sources

## GitHub Repos (Source of Truth)

| Repo | Stars | Tools | Install Method |
|------|-------|-------|----------------|
| [onex](https://github.com/jackind424/onex) | 848 | 370 | `sh onex/install` |
| [hackingtool](https://github.com/Z4nzu/hackingtool) | 76,650 | 185 | `sudo ./hackingtool/install.sh` |
| [WebHackersWeapons](https://github.com/hahwul/WebHackersWeapons) | 4,611 | 429 | Tool catalog only (no installer) |
| [Scrapling](https://github.com/D4Vinci/Scrapling) | 55,000 | — | `pip install scrapling[all]` |
| [DeepLX](https://github.com/OwO-Network/DeepLX) | 8,511 | — | Binary download |

## Top Tools by Stars (Not in Default Catalogs)

| Tool | Stars | Repo |
|------|-------|------|
| metasploit-framework | 38,269 | rapid7/metasploit-framework |
| sqlmap | 37,508 | sqlmapproject/sqlmap |
| web-check | 33,246 | lissy93/web-check |
| nuclei | 28,943 | projectdiscovery/nuclei |
| mimikatz | 21,590 | gentilkiwi/mimikatz |
| spiderfoot | 17,984 | smicallef/spiderfoot |
| katana | 16,875 | projectdiscovery/katana |
| ffuf | 16,157 | ffuf/ffuf |
| lynis | 15,701 | CISOfy/lynis |
| zaproxy | 15,200 | zaproxy/zaproxy |
| amass | 14,636 | owasp-amass/amass |
| nmap | 12,966 | nmap/nmap |
| thc-hydra | 11,837 | vanhauser-thc/thc-hydra |
| sliver | 11,277 | BishopFox/sliver |
| BloodHound | 10,541 | BloodHoundAD/BloodHound |

## System Dependencies

| Package | Purpose | Install |
|---------|---------|---------|
| tor | Onion routing | `apt install tor` |
| proxychains4 | Traffic proxying | `apt install proxychains4` |
| python3 | Runtime | System |
| git | Repo cloning | System |

## Python Packages

| Package | Version | Purpose |
|---------|---------|---------|
| scrapling | 0.4.8 | Web scraping |
| patchright | 1.59.1 | Anti-detection browser |
| playwright | 1.59.0 | Browser automation |
| curl_cffi | 0.15.0 | TLS fingerprint impersonation |
| markdownify | 1.2.2 | HTML → Markdown (for CLI) |

## Reinstall

```bash
bash /root/workspace/hermes-reinstall.sh
```
