#!/bin/bash
# Oracle AI Infrastructure Verification Script

# This script verifies the Oracle AI Infrastructure setup
# Usage: /tmp/verify_oracle_ai.sh

# Configuration
LOG_FILE="/tmp/verification.log"
CONFIG_FILE="/home/oracle/orai_config.conf"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check Python
    if command -v python3 >/dev/null 2>&1; then
        log "✅ Python3 is available: $(python3 --version)"
    else
        log "❌ Python3 is not available"
        return 1
    fi
    
    # Check virtual environment
    if [ -d "/tmp/hermes-ai-venv" ]; then
        log "✅ Virtual environment exists"
    else
        log "❌ Virtual environment not found"
        return 1
    fi
    
    # Check psutil
    if /tmp/hermes-ai-venv/bin/python3 -c "import psutil" 2>/dev/null; then
        log "✅ psutil is available"
    else
        log "❌ psutil is not available"
        return 1
    fi
}

# Function to check Oracle Free Tier resources
check_oracle_resources() {
    log "Checking Oracle Free Tier resources..."
    
    # Check model file
    if [ -f "/tmp/ai-models/model-q4_k.gguf" ]; then
        MODEL_SIZE=$(du -h "/tmp/ai-models/model-q4_k.gguf" | cut -f1)
        log "✅ Model file exists: $MODEL_SIZE"
    else
        log "❌ Model file not found"
        return 1
    fi
    
    # Check system resources
    RAM_AVAILABLE=$(free -m | awk 'NR==2{printf "%.0f", $4}')
    CPU_CORES=$(nproc)
    
    if [ $RAM_AVAILABLE -ge 8 ]; then
        log "✅ RAM available: ${RAM_AVAILABLE}MB"
    else
        log "❌ Insufficient RAM: ${RAM_AVAILABLE}MB (minimum 8GB)"
        return 1
    fi
    
    if [ $CPU_CORES -ge 2 ]; then
        log "✅ CPU cores available: $CPU_CORES"
    else
        log "❌ Insufficient CPU cores: $CPU_CORES (minimum 2)"
        return 1
    fi
}

# Function to check service status
check_service_status() {
    log "Checking service status..."
    
    # Check if inference process is running
    if /tmp/oracle_manager.sh status >/dev/null 2>&1; then
        log "✅ Oracle AI Inference is running"
    else
        log "❌ Oracle AI Inference is not running"
        return 1
    fi
    
    # Check cron jobs
    CRON_COUNT=$(crontab -l | grep oracle_heartbeat.sh | wc -l)
    if [ $CRON_COUNT -gt 0 ]; then
        log "✅ Cron jobs configured: $CRON_COUNT"
    else
        log "❌ No cron jobs configured"
        return 1
    fi
}

# Function to check logs
check_logs() {
    log "Checking logs..."
    
    # Check heartbeat log
    if [ -f "/home/oracle/hermes_heartbeat.log" ]; then
        HEARTBEAT_SIZE=$(du -h "/home/oracle/hermes_heartbeat.log" | cut -f1)
        log "✅ Heartbeat log exists: $HEARTBEAT_SIZE"
        
        # Check recent activity
        RECENT_ENTRIES=$(tail -5 "/home/oracle/hermes_heartbeat.log" | wc -l)
        log "   Recent entries: $RECENT_ENTRIES"
    else
        log "❌ Heartbeat log not found"
        return 1
    fi
    
    # Check inference log
    if [ -f "/tmp/hermes-ai-inference.log" ] && [ -s "/tmp/hermes-ai-inference.log" ]; then
        log "✅ Inference log exists and has content"
    else
        log "⚠️  Inference log empty or not found"
    fi
}

# Function to run tests
run_tests() {
    log "Running basic tests..."
    
    # Test heartbeat functionality
    if /tmp/oracle_heartbeat.sh >/dev/null 2>&1; then
        log "✅ Heartbeat script executes successfully"
    else
        log "❌ Heartbeat script failed"
        return 1
    fi
    
    # Test service management
    if /tmp/oracle_manager.sh status >/dev/null 2>&1; then
        log "✅ Service management works correctly"
    else
        log "❌ Service management failed"
        return 1
    fi
    
    # Test verification script
    if /tmp/verify_setup.sh >/dev/null 2>&1; then
        log "✅ Verification script executes successfully"
    else
        log "❌ Verification script failed"
        return 1
    fi
}

# Function to generate report
 generate_report() {
    log "" >> $LOG_FILE
    log "Oracle AI Infrastructure Verification Report" >> $LOG_FILE
    log "=" * 50 >> $LOG_FILE
    log "Generated: $(date)" >> $LOG_FILE
    log "" >> $LOG_FILE
    
    # System information
    log "System Information:" >> $LOG_FILE
    log "  OS: $(uname -s) $(uname -r)" >> $LOG_FILE
    log "  Architecture: $(uname -m)" >> $LOG_FILE
    log "  Python: $(python3 --version)" >> $LOG_FILE
    log "  Shell: $SHELL" >> $LOG_FILE
    log "" >> $LOG_FILE
    
    # Resource information
    log "Resource Information:" >> $LOG_FILE
    log "  RAM: $(free -h | grep Mem | awk '{print $2}')" >> $LOG_FILE
    log "  CPU: $(nproc) cores" >> $LOG_FILE
    log "  Disk: $(df -h / | tail -1 | awk '{print $5}')" >> $LOG_FILE
    log "" >> $LOG_FILE
    
    # Oracle Free Tier resources
    log "Oracle Free Tier Resources:" >> $LOG_FILE
    log "  CPU: 4 OCPU cores" >> $LOG_FILE
    log "  Memory: 24GB RAM" >> $LOG_FILE
    log "  Storage: 200GB" >> $LOG_FILE
    log "  Bandwidth: 10TB" >> $LOG_FILE
    log "" >> $LOG_FILE
    
    # Infrastructure components
    log "Infrastructure Components:" >> $LOG_FILE
    log "  Virtual Environment: /tmp/hermes-ai-venv" >> $LOG_FILE
    log "  Model Directory: /tmp/ai-models" >> $LOG_FILE
    log "  Heartbeat Log: /home/oracle/hermes_heartbeat.log" >> $LOG_FILE
    log "  Inference Log: /tmp/hermes-ai-inference.log" >> $LOG_FILE
    log "  Configuration: /home/oracle/orai_config.conf" >> $LOG_FILE
    log "" >> $LOG_FILE
    
    # Status summary
    log "Status Summary:" >> $LOG_FILE
    log "  System Requirements: $(check_system_requirements && echo 'PASS' || echo 'FAIL')" >> $LOG_FILE
    log "  Oracle Resources: $(check_oracle_resources && echo 'PASS' || echo 'FAIL')" >> $LOG_FILE
    log "  Service Status: $(check_service_status && echo 'PASS' || echo 'FAIL')" >> $LOG_FILE
    log "  Logs Status: $(check_logs && echo 'PASS' || echo 'FAIL')" >> $LOG_FILE
    log "  Tests Status: $(run_tests && echo 'PASS' || echo 'FAIL')" >> $LOG_FILE
    log "" >> $LOG_FILE
    
    # Conclusion
    local overall_status="PASS"
    if ! check_system_requirements || ! check_oracle_resources || ! check_service_status || ! check_logs || ! run_tests; then
        overall_status="FAIL"
    fi
    
    log "Overall Status: $overall_status" >> $LOG_FILE
    
    if [ "$overall_status" = "PASS" ]; then
        log "" >> $LOG_FILE
        log "🎉 Oracle AI Infrastructure setup is working correctly!" >> $LOG_FILE
    else
        log "" >> $LOG_FILE
        log "❌ Oracle AI Infrastructure setup has issues that need to be resolved." >> $LOG_FILE
    fi
}

# Main execution
main() {
    log "Starting Oracle AI Infrastructure Verification"
    log "=" * 50
    
    # Initialize log file
    > $LOG_FILE
    
    # Run checks
    check_system_requirements
    echo
    check_oracle_resources
    echo
    check_service_status
    echo
    check_logs
    echo
    run_tests
    echo
    
    # Generate detailed report
    generate_report
    
    # Display summary
    echo ""
    echo "Oracle AI Infrastructure Verification Complete"
    echo "=" * 50
    echo "Log file: $LOG_FILE"
    echo ""
    echo "Next Steps:"
    echo "1. Check the log file for detailed information"
    echo "2. Review any failed checks"
    echo "3. Run the verification script again after fixing issues"
    echo ""
    echo "Commands:"
    echo "  Check status: /tmp/oracle_manager.sh status"
    echo "  View logs: /tmp/oracle_manager.sh logs"
    echo "  Run verification: /tmp/verify_setup.sh"
}

# Execute main function
main
