#!/bin/bash
# Oracle AI Infrastructure Template

# This template demonstrates how to set up Oracle Cloud Always Free AI infrastructure
# Copy this file and modify the variables to match your requirements

# Configuration variables
ORACLE_REGION="us-ashburn-1"
OCI_CLI_VERSION="3.0.0"
MODEL_NAME="huihui-gemma-4-E2B-it-qat-q4_0-unquantized-abliterated"
MODEL_SIZE_GB=3
INFERENCE_PORT=8000
HEARTBEAT_INTERVAL=15

# Model configuration
export MODEL_NAME
export MODEL_SIZE_GB
export INFERENCE_PORT
export HEARTBEAT_INTERVAL

# System requirements
export ORACLE_CPU=4
export ORACLE_MEMORY=24
export ORACLE_STORAGE=200
export ORACLE_BANDWIDTH=10

# Network configuration
export ORACLE_VCN_ID="ocid1.vcn.oc1..example1"
export ORACLE_SUBNET_ID="ocid1.subnet.oc1..example2"
export ORACLE_SECURITY_LIST_ID="ocid1.securitylist.oc1..example3"

# Create infrastructure
echo "🚀 Setting up Oracle AI Infrastructure"
echo "Region: $ORACLE_REGION"
echo "Model: $MODEL_NAME"
echo "CPU: $ORACLE_CPU cores"
echo "Memory: $ORACLE_MEMORY GB"
echo "Storage: $ORACLE_STORAGE GB"
echo "Heartbeat Interval: $HEARTBEAT_INTERVAL minutes"

# Create model directory
mkdir -p /tmp/ai-models
mkdir -p /home/oracle
chmod 755 /home/oracle

# Download model (placeholder - replace with actual download command)
echo "📥 Downloading model..."
echo "Model size: ${MODEL_SIZE_GB}GB"
echo "This is a placeholder - replace with actual download command"

# Set up cron jobs
echo "⏰ Setting up cron jobs..."
(crontab -l 2>/dev/null; echo "*/$HEARTBEAT_INTERVAL * * * * /tmp/oracle_heartbeat.sh") | crontab -

# Start services
echo "🔄 Starting services..."
/tmp/oracle_manager.sh start

# Verify setup
echo "✅ Setup completed"
/tmp/verify_setup.sh

echo ""
echo "🎉 Oracle AI Infrastructure setup complete!"
echo ""
echo "Quick commands:"
echo "  Status:  /tmp/oracle_manager.sh status"
echo "  Logs:    /tmp/oracle_manager.sh logs"
echo "  Heartbeat: /tmp/oracle_heartbeat.sh"
echo "  Verify: /tmp/verify_setup.sh"

# Save configuration
cat > /home/oracle/orai_config.conf << EOF
# Oracle AI Infrastructure Configuration
REGION=$ORACLE_REGION
MODEL_NAME=$MODEL_NAME
MODEL_SIZE_GB=$MODEL_SIZE_GB
INFERENCE_PORT=$INFERENCE_PORT
HEARTBEAT_INTERVAL=$HEARTBEAT_INTERVAL
CPU=$ORACLE_CPU
MEMORY=$ORACLE_MEMORY
STORAGE=$ORACLE_STORAGE
BANDWIDTH=$ORACLE_BANDWIDTH

# Set environment variables
export ORACLE_REGION
export ORACLE_CPU
export ORACLE_MEMORY
export ORACLE_STORAGE
export ORACLE_BANDWIDTH
EOF

echo "Configuration saved to /home/oracle/orai_config.conf"
