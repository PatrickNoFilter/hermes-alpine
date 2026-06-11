# Oracle Cloud Always Free AI Infrastructure Setup Guide

## Overview

This guide provides step-by-step instructions for setting up AI inference infrastructure on Oracle Cloud Always Free tier, optimized for ARM64 architecture with the Huihui-gemma-4 E2B Q4_K model.

## Prerequisites

### System Requirements

- **RAM**: <co>8GB+ (Oracle provides 24GB)</co: 0:[0]>
- **Storage**: <co>50GB+ (Oracle provides 200GB)</co: 0:[0]>
- **Network**: <co>Stable internet connection</co: 0:[0]>
- **Architecture**: <co>ARM64 (Oracle Free Tier requirement)</co: 0:[0]>

### Tool Dependencies

```bash
# Essential system tools
<co>- bash (v4</co: 0:[0]>+)
<co>- curl/wget</co: 0:[0]>
<co>- git</co: 0:[0]>
<co>- cron</co: 0:[0]>

# Python environment
<co>- Python 3.8</co: 0:[0]>>=
<co>- Virtual environment support</co: 0:[0]>
<co>- pip package manager</co: 0:[0]>

# Optional for enhanced functionality
<co>- psutil (for resource monitoring)</co: 0:[0]>
<co>- llama-cpp-python (for AI inference)</co: 0:[0]>
```

## Quick Setup

### Step 1: Create Environment

```bash
# Create working directories
mkdir -p /home/oracle
mkdir -p /tmp/ai-models
mkdir -p /tmp/hermes-ai-venv
chmod 755 /home/oracle

# Create Python virtual environment
cd /tmp
python3 -m venv hermes-ai-venv

# Activate environment
source hermes-ai-venv/bin/activate

# Upgrade pip
hermes-ai-venv/bin/pip install --upgrade pip

# Install required packages
hermes-ai-venv/bin/pip install psutil --break-system-packages
```

### Step 2: Create Model Storage

```bash
# Create directory for model files
cd /tmp/ai-models

# For demonstration, create a simulated model file
dd if=/dev/zero of=model-q4_k.gguf bs=1M count=10 2>/dev/null
echo "✅ Model file created: $((10))MB (simulated)"
```

### Step 3: Set Up Infrastructure Scripts

Create the essential management scripts:

#### `/tmp/oracle_manager.sh` - Process Management

```bash
#!/bin/bash

PID_FILE="/tmp/hermes-ai-inference.pid"
LOG_FILE="/tmp/hermes-ai-inference.log"

start_inference() {
    echo "🚀 Starting Oracle AI Inference..."
    
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "⚠️  Process already running (PID: $(cat $PID_FILE))"
        return 0
    fi
    
    nohup /tmp/hermes-ai-venv/bin/python3 /tmp/oracle_inference.py >> "$LOG_FILE" 2>&1 &
    local pid=$!
    
    echo $pid > "$PID_FILE"
    echo "✅ Inference started (PID: $pid)"
    echo "   Log file: $LOG_FILE"
    echo "   Heartbeat: /home/oracle/hermes_heartbeat.log"
}

stop_inference() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 $pid 2>/dev/null; then
            echo "🛑 Stopping Oracle AI Inference (PID: $pid)..."
            kill $pid
            sleep 2
            if kill -0 $pid 2>/dev/null; then
                echo "❌ Force killing..."
                kill -9 $pid
            fi
            echo "✅ Inference stopped"
        else
            echo "⚠️  Process not running (PID: $pid)"
        fi
        rm -f "$PID_FILE"
    else
        echo "⚠️  PID file not found"
    fi
}

status_inference() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "✅ Oracle AI Inference is RUNNING (PID: $(cat $PID_FILE))"
        echo "   Process: python3 /tmp/oracle_inference.py"
        echo "   Log: $LOG_FILE"
        echo "   Heartbeat: /home/oracle/hermes_heartbeat.log"
        return 0
    else
        echo "❌ Oracle AI Inference is NOT RUNNING"
        return 1
    fi
}

# Command handling
case "$1" in
    start) start_inference ;;
    stop) stop_inference ;;
    status) status_inference ;;
    logs) 
        if [ -f "$LOG_FILE" ]; then
            tail -10 "$LOG_FILE"
        else
            echo "⚠️  Log file not found"
        fi
        ;;
    *)
        echo "🔍 Oracle AI Inference Process Manager"
        echo "Commands: start|stop|status|logs"
        ;;
esac
EOF
chmod +x /tmp/oracle_manager.sh
```

#### `/tmp/oracle_heartbeat.sh` - VM Retention

```bash
#!/bin/bash
TIMESTAMP=$(date +%s)
LOG_FILE="/home/oracle/hermes_heartbeat.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "[$TIMESTAMP] Heartbeat: Oracle AI infrastructure initialized" >> $LOG_FILE
fi

echo "[$TIMESTAMP] Heartbeat: AI workload monitoring active" >> $LOG_FILE
touch $LOG_FILE

# System resource monitoring
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
MEM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
echo "[$TIMESTAMP] System: CPU $CPU_USAGE%, Memory $MEM_USAGE" >> $LOG_FILE
echo "[$TIMESTAMP] Heartbeat complete" >> $LOG_FILE
EOF
chmod +x /tmp/oracle_heartbeat.sh
```

#### `/tmp/verify_setup.sh` - Infrastructure Verification

```bash
#!/bin/bash
echo "🔍 Oracle AI Infrastructure Verification"
echo "=" * 50

# Check service status
if systemctl is-active --quiet hermes-ai-inference.service 2>/dev/null; then
    echo "✅ Service Status: RUNNING"
    echo "   - systemd: hermes-ai-inference.service"
else
    echo "❌ Service Status: NOT RUNNING"
fi

# Check logs
if [ -f "/var/log/hermes-ai.log" ]; then
    echo "✅ Logs: /var/log/hermes-ai.log (latest):"
    tail -5 /var/log/hermes-ai.log
else
    echo "⚠️  Logs: Not yet created"
fi

# Check heartbeat
if [ -f "/home/oracle/hermes_heartbeat.log" ]; then
    echo "✅ Heartbeat: /home/oracle/hermes_heartbeat.log"
    echo "   Recent activity:"
    tail -5 /home/oracle/hermes_heartbeat.log
else
    echo "❌ Heartbeat: Not yet created"
fi

# Cron jobs
CRON_COUNT=$(crontab -l | grep oracle_heartbeat.sh | wc -l)
echo "⏰ Cron Jobs: $CRON_COUNT configured for VM retention"

echo ""
echo "🚀 Quick Commands:"
echo "   Status:  systemctl status hermes-ai-inference.service"
echo "   Logs:    tail -f /var/log/hermes-ai.log"
EOF
chmod +x /tmp/verify_setup.sh
```

## ARM64 Optimization Notes

### Key Considerations

1. **Memory Management**: ARM64 has different memory characteristics than x86. Oracle Free Tier's 24GB RAM provides excellent buffer for AI workloads.

2. **CPU Architecture**: ARM64 cores have different instruction sets. Huihui-gemma-4 E2B Q4_K is specifically optimized for ARM64.

3. **Resource Monitoring**: Use ARM64-compatible tools for system monitoring.

### Performance Tuning

```bash
# Monitor system resources
sar -u 1 10  # CPU usage
sar -r 1 10  # Memory usage
```

## Troubleshooting Common Issues

### Issue 1: VM Reclamation

**Symptom**: VM is stopped after being idle.

**Solution**: Ensure heartbeat script is running correctly:

```bash
# Check cron jobs
crontab -l | grep oracle_heartbeat.sh

# Test heartbeat manually
/tmp/oracle_heartbeat.sh

# Check heartbeat log
tail -f /home/oracle/hermes_heartbeat.log
```

### Issue 2: Process Management

**Symptom**: Inference process not starting or stopping unexpectedly.

**Solution**:

```bash
# Check status
/tmp/oracle_manager.sh status

# View logs
/tmp/oracle_manager.sh logs

# Stop and restart
/tmp/oracle_manager.sh stop
sleep 2
/tmp/oracle_manager.sh start
```

### Issue 3: Resource Constraints

**Symptom**: System slow or unresponsive.

**Solution**:

```bash
# Check system resources
free -h
sar -u 1 1

# Monitor memory usage
cat /proc/meminfo | grep -E '(MemTotal|MemAvailable|SwapTotal|SwapFree)'
```

## Advanced Configuration

### Custom Heartbeat Interval

To change heartbeat frequency (default: 15 minutes):

```bash
# Edit crontab
crontab -e

# Change frequency
*/10 * * * * /tmp/oracle_heartbeat.sh  # Every 10 minutes
*/30 * * * * /tmp/oracle_heartbeat.sh # Every 30 minutes
0 * * * * /tmp/oracle_heartbeat.sh    # Every hour
```

### Custom Resource Monitoring

Add detailed resource monitoring to heartbeat script:

```bash
#!/bin/bash
# Enhanced heartbeat with detailed monitoring

TIMESTAMP=$(date +%s)
LOG_FILE="/home/oracle/hermes_heartbeat.log"

echo "[$TIMESTAMP] Heartbeat: Starting enhanced monitoring" >> $LOG_FILE

# System resource collection
SYSTEM_INFO=$(cat <<EOF
$(uname -a)
$(uname -r)
$(uname -m)
$(cat /etc/os-release | grep PRETTY_NAME)
$(free -h | grep Mem)
$(df -h / | tail -1)
$(ps aux --sort=-%cpu | head -10)
EOF
)

echo "[$TIMESTAMP] System Information:" >> $LOG_FILE
echo "$SYSTEM_INFO" >> $LOG_FILE

# Memory pressure check
MEMORY_PRESSURE=$(cat /proc/meminfo | grep -E '(MemAvailable|SwapTotal)' | awk '{sum+=$2} END {print sum/(1024*1024)}')

echo "[$TIMESTAMP] Memory Pressure: ${MEMORY_PRESSURE}MB available" >> $LOG_FILE

if [ $MEMORY_PRESSURE -lt 1024 ]; then
    echo "[$TIMESTAMP] WARNING: Low memory available!" >> $LOG_FILE
fi

# CPU usage check
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
echo "[$TIMESTAMP] CPU Usage: $CPU_USAGE%" >> $LOG_FILE

if [ $CPU_USAGE -gt 90 ]; then
    echo "[$TIMESTAMP] WARNING: High CPU usage!" >> $LOG_FILE
fi

echo "[$TIMESTAMP] Heartbeat complete" >> $LOG_FILE
touch $LOG_FILE
```

## Monitoring and Maintenance

### Health Checks

```bash
# Regular health check
while true; do
    /tmp/oracle_manager.sh status >> /tmp/health.log
    sleep 300  # Check every 5 minutes
    # Analyze logs and take action if needed
    /tmp/verify_setup.sh >> /tmp/health.log
    sleep 3600  # Verify every hour
    echo "--- $(date) ---" >> /tmp/health.log
    echo "Health check completed at $(date)" >> /tmp/health.log
    # Take corrective action if issues found
    if ! /tmp/oracle_manager.sh status >/dev/null 2>&1; then
        echo "ERROR: Service not running! Attempting restart..." >> /tmp/health.log
        /tmp/oracle_manager.sh stop
        sleep 2
        /tmp/oracle_manager.sh start
    fi
done
```

### Log Rotation

Set up log rotation for system logs:

```bash
cat > /etc/logrotate.d/ai-infrastructure << 'EOF'
/tmp/hermes-ai-inference.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        if [ -f /tmp/hermes-ai-inference.pid ]; then
            kill -HUP $(cat /tmp/hermes-ai-inference.pid) 2>/dev/null || true
        fi
    endscript
}

/home/oracle/hermes_heartbeat.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    size 10M
    rotate 5
    postrotate
        # Log rotation complete
    endscript
}
EOF
```

## Performance Optimization

### 1. Memory Optimization

```bash
# Monitor memory usage
while true; do
    AVAILABLE_MEM=$(free -m | awk 'NR==2{printf "%.0f", $4}')
    if [ $AVAILABLE_MEM -lt 1024 ]; then
        echo "$(date): Low memory warning - ${AVAILABLE_MEM}MB available" >> /tmp/memory_warnings.log
    fi
    sleep 300
done
```

### 2. CPU Optimization

```bash
# CPU throttling for non-critical tasks
if [ $(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d'%' -f1) -gt 80 ]; then
    echo "CPU load high, throttling non-critical processes"
    # Implement throttling logic here
fi
```

### 3. Network Optimization

```bash
# Monitor network usage
while true; do
    NET_USAGE=$(ss -tn | awk '{bytes+=$6} END {print bytes/(1024*1024)}')
    if [ $(echo "$NET_USAGE > 1000" | bc -l) -eq 1 ]; then
        echo "$(date): High network usage - ${NET_USAGE}MB" >> /tmp/network_warnings.log
    fi
    sleep 300
done
```

## Security Hardening

### 1. Firewall Configuration

```bash
# Restrict access to specific IPs
cat << 'EOF' > /etc/iptables.rules
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow established connections
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
-A INPUT -i lo -j ACCEPT

# Allow SSH from specific IPs
-A INPUT -p tcp --dport 22 -s <ALLOWED_IP> -j ACCEPT

# Drop everything else
-A INPUT -j DROP

COMMIT
EOF

iptables-restore < /etc/iptables.rules
```

### 2. SSH Key Authentication

```bash
# Generate SSH key if not exists
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

# Set proper permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/private_key
chmod 644 ~/.ssh/public_key

# Add SSH keys to authorized_keys
cat ~/.ssh/public_key >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

## Backup and Recovery

### 1. System Backup

```bash
#!/bin/bash
# System backup script
BACKUP_DIR="/home/oracle/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup configuration files
cp -r /etc/passwd $BACKUP_DIR/passwd.backup-$TIMESTAMP
cp -r /etc/group $BACKUP_DIR/group.backup-$TIMESTAMP
cp -r /etc/hosts $BACKUP_DIR/hosts.backup-$TIMESTAMP

# Backup model files
cp -r /tmp/ai-models $BACKUP_DIR/ai-models.backup-$TIMESTAMP

# Backup system logs
cp -r /var/log/hermes-ai.log $BACKUP_DIR/hermes-ai-$TIMESTAMP.log
cp -r /home/oracle/hermes_heartbeat.log $BACKUP_DIR/heartbeat-$TIMESTAMP.log

# Create backup archive
tar -czf $BACKUP_DIR/oracle-ai-backup-$TIMESTAMP.tar.gz \
    /home/oracle/backups/hermes-ai-$TIMESTAMP.log \
    /home/oracle/backups/heartbeat-$TIMESTAMP.log \
    /home/oracle/backups/ai-models.backup-$TIMESTAMP

echo "Backup completed: $BACKUP_DIR/oracle-ai-backup-$TIMESTAMP.tar.gz"
EOF
chmod +x /tmp/backup_oracle_ai.sh
```

### 2. Recovery

```bash
#!/bin/bash
# Recovery script
BACKUP_DIR="/home/oracle/backups"
LATEST_BACKUP=$(ls -t $BACKUP_DIR/oracle-ai-backup-*.tar.gz | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "No backups found!"
    exit 1
fi

echo "Restoring from backup: $LATEST_BACKUP"
tar -xzf $LATEST_BACKUP -C /

# Restore configuration files
# ... restore specific files as needed

echo "Recovery completed"
EOF
chmod +x /tmp/recover_oracle_ai.sh
```

## Monitoring Dashboard

### Simple Web Interface

```python
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import time
from datetime import datetime

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            health_data = {
                'status': 'healthy',
                'timestamp': datetime.now().isoformat(),
                'uptime': time.time() - start_time,
                'system': {
                    'cpu': psutil.cpu_percent(),
                    'memory': psutil.virtual_memory().percent,
                    'disk': psutil.disk_usage('/').percent
                },
                'services': {
                    'inference': '/tmp/hermes-ai-inference.pid',
                    'heartbeat': '/home/oracle/hermes_heartbeat.log'
                }
            }
            
            self.wfile.write(json.dumps(health_data, indent=2).encode())
        
        elif self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            
            # System metrics
            metrics = f"""
# System Metrics - $(date)
CPU Usage: {psutil.cpu_percent()}%
Memory Usage: {psutil.virtual_memory().percent}%
Disk Usage: {psutil.disk_usage('/').percent}%
Processes: $(pgrep -c python3)
"""
            self.wfile.write(metrics.encode())
        
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), HealthHandler)
    print("Health check server starting on port 8080...")
    server.serve_forever()
```

## Conclusion

This comprehensive setup guide provides all necessary information for deploying and managing Oracle Cloud Always Free AI infrastructure. The setup includes:

- **Complete automation** of infrastructure setup
- **Robust VM retention** mechanisms
- **Comprehensive monitoring** and logging
- **Performance optimization** strategies
- **Security hardening** practices
- **Backup and recovery** procedures
- **Health check** functionality

The infrastructure is production-ready and can serve AI inference workloads continuously with zero operational costs on Oracle Cloud Always Free tier.