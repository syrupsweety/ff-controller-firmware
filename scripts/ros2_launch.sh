#!/usr/bin/env bash
#===============================================================================
# File: scripts/ros2_launch.sh
# Description: Simplified ROS2 driver launcher for RP2350 controller
# Usage: ./scripts/ros2_launch.sh [--device <path>] [--address <addr>] [--rate <hz>]
# License: MIT
#===============================================================================

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROS2_WS="${PROJECT_ROOT}/ros2_ws"

# Defaults
I2C_DEVICE="/dev/i2c-1"
I2C_ADDRESS=8
PUBLISH_RATE=50
LAUNCH_MODE="full"  # full | driver | monitor | test

# Logging functions
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
log_step()    { echo -e "${CYAN}[→]${NC} $*"; }
log_ros2()    { echo -e "${MAGENTA}[ROS2]${NC} $*"; }

# Print banner
print_banner() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}        ${BLUE}RP2350 ROS2 Driver Launcher${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [MODE]

MODES:
  full      Launch driver + monitor topics (default)
  driver    Launch only the driver node
  monitor   Only monitor existing topics (no driver)
  test      Run diagnostic tests only

OPTIONS:
  --device, -d <path>   I2C device path (default: /dev/i2c-1)
  --address, -a <addr>  I2C address in decimal (default: 8 = 0x08)
  --rate, -r <hz>       Publish rate in Hz (default: 50)
  --verbose, -v         Enable verbose/debug logging
  --help, -h            Show this help message

EXAMPLES:
  # Launch with defaults
  ./scripts/ros2_launch.sh
  
  # Custom I2C device
  ./scripts/ros2_launch.sh --device /dev/i2c-2
  
  # Different I2C address (e.g., 0x10 = 16)
  ./scripts/ros2_launch.sh --address 16
  
  # Higher publish rate
  ./scripts/ros2_launch.sh --rate 100
  
  # Driver only (no monitor)
  ./scripts/ros2_launch.sh driver
  
  # Just monitor existing topics
  ./scripts/ros2_launch.sh monitor
  
  # Run diagnostics
  ./scripts/ros2_launch.sh test

QUICK START:
  1. Ensure firmware is flashed to RP2350
  2. Connect RP2350 I2C to host (SDA, SCL, GND)
  3. Run: ./scripts/ros2_launch.sh
  4. In new terminal: ros2 topic pub /controller/motor_command ...

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                I2C_DEVICE="$2"
                shift 2
                ;;
            --address|-a)
                I2C_ADDRESS="$2"
                shift 2
                ;;
            --rate|-r)
                PUBLISH_RATE="$2"
                shift 2
                ;;
            --verbose|-v)
                export RCUTILS_CONSOLE_OUTPUT_FORMAT="{time} [{severity}] {name}: {message}"
                VERBOSE=true
                shift
                ;;
            full|driver|monitor|test)
                LAUNCH_MODE="$1"
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# Check ROS2 environment
check_ros2_environment() {
    log_step "Checking ROS2 environment..."
    
    # Check ROS2 installation
    if ! command -v ros2 &>/dev/null; then
        log_error "ROS2 not found in PATH"
        log_info "Source your ROS2 setup.bash first:"
        log_info "  source /opt/ros/humble/setup.bash  # Adjust for your distro"
        exit 1
    fi
    log_success "ROS2 found: ${ROS_DISTRO:-unknown}"
    
    # Check workspace
    if [[ ! -d "${ROS2_WS}/install" ]]; then
        log_warn "ROS2 workspace not built: ${ROS2_WS}"
        log_info "Build first: ./scripts/build_and_test.sh ros2"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        log_success "ROS2 workspace found: ${ROS2_WS}"
        # Source workspace
        source "${ROS2_WS}/install/setup.bash"
        log_success "Workspace sourced"
    fi
    
    # Check I2C device
    if [[ ! -e "${I2C_DEVICE}" ]]; then
        log_warn "I2C device not found: ${I2C_DEVICE}"
        log_info "Check I2C is enabled: sudo raspi-config (on Raspberry Pi)"
        log_info "Or list devices: ls /dev/i2c-*"
    else
        log_success "I2C device available: ${I2C_DEVICE}"
    fi
}

# Check I2C connection
check_i2c_connection() {
    log_step "Checking I2C connection..."
    
    if ! command -v i2cdetect &>/dev/null; then
        log_warn "i2cdetect not available. Install i2c-tools:"
        log_info "  sudo apt install i2c-tools"
        return 0
    fi
    
    # Scan for device
    local detected=false
    if i2cdetect -y -r "$(echo "${I2C_DEVICE}" | sed 's/.*i2c-//')" 2>/dev/null | grep -qi "$(printf '%02x' "${I2C_ADDRESS}")"; then
        log_success "Controller detected at I2C address 0x$(printf '%02x' "${I2C_ADDRESS}")"
        detected=true
    else
        log_warn "Controller NOT detected at I2C address 0x$(printf '%02x' "${I2C_ADDRESS}")"
        log_info "Check:"
        log_info "  • Wiring (SDA, SCL, GND)"
        log_info "  • Firmware is running on RP2350"
        log_info "  • I2C address in firmware matches (default: 0x08)"
    fi
    
    return 0
}

# Launch driver node
launch_driver() {
    log_step "Launching controller driver node..."
    log_info "I2C Device: ${I2C_DEVICE}"
    log_info "I2C Address: ${I2C_ADDRESS} (0x$(printf '%02x' "${I2C_ADDRESS}"))"
    log_info "Publish Rate: ${PUBLISH_RATE} Hz"
    echo ""
    
    # Build launch command
    local launch_cmd="ros2 launch controller_driver controller_driver.launch.py"
    launch_cmd+=" i2c_device:=${I2C_DEVICE}"
    launch_cmd+=" i2c_address:=${I2C_ADDRESS}"
    launch_cmd+=" publish_rate_hz:=${PUBLISH_RATE}"
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        launch_cmd+=" --ros-args --log-level debug"
    fi
    
    log_ros2 "Executing: ${launch_cmd}"
    echo ""
    
    # Launch (this will block)
    eval "${launch_cmd}"
}

# Monitor topics
monitor_topics() {
    log_step "Monitoring controller topics..."
    echo ""
    
    # Check if topics exist
    if ! ros2 topic list 2>/dev/null | grep -q "controller"; then
        log_warn "No controller topics found"
        log_info "Start the driver first: ./scripts/ros2_launch.sh driver"
        return 1
    fi
    
    # List topics
    log_success "Available controller topics:"
    ros2 topic list | grep controller | sed 's/^/  /'
    echo ""
    
    # Echo main topics (in background)
    log_info "Monitoring /controller/input (Ctrl+C to stop)..."
    echo ""
    
    ros2 topic echo /controller/input --once 2>/dev/null || {
        log_warn "Could not echo topic (driver may not be running)"
    }
}

# Run diagnostics
run_diagnostics() {
    log_step "Running ROS2 diagnostics..."
    echo ""
    
    # Test 1: ROS2 system check
    log_info "Test 1: ROS2 system health"
    if command -v ros2 &>/dev/null; then
        ros2 doctor --report 2>/dev/null | head -20 || log_warn "ros2 doctor unavailable"
    fi
    echo ""
    
    # Test 2: Package check
    log_info "Test 2: Package verification"
    if ros2 pkg list 2>/dev/null | grep -q "controller"; then
        log_success "Controller packages found"
        ros2 pkg list | grep controller | sed 's/^/  /'
    else
        log_warn "Controller packages not found"
    fi
    echo ""
    
    # Test 3: Message types
    log_info "Test 3: Message type verification"
    for msg in ControllerInput MotorCommand; do
        if ros2 interface show controller_msgs/msg/${msg} &>/dev/null; then
            log_success "✓ controller_msgs/msg/${msg}"
        else
            log_warn "✗ controller_msgs/msg/${msg}"
        fi
    done
    echo ""
    
    # Test 4: I2C check
    log_info "Test 4: I2C bus check"
    check_i2c_connection
    echo ""
    
    # Test 5: Topic check
    log_info "Test 5: Active topics"
    if ros2 topic list 2>/dev/null | grep -q "controller"; then
        log_success "Controller topics active"
        ros2 topic hz /controller/input 2>&1 | head -5 || true
    else
        log_warn "No active controller topics"
    fi
    echo ""
    
    log_success "Diagnostics complete"
}

# Launch full mode (driver + monitor in background)
launch_full() {
    log_step "Launching full mode (driver + monitor)..."
    echo ""
    
    # Check if tmux is available for split panes
    if command -v tmux &>/dev/null; then
        log_info "tmux available - creating session with split panes"
        
        # Create tmux session
        tmux new-session -d -s rp2350_controller
        tmux split-window -v -t rp2350_controller
        
        # Driver in top pane
        tmux send-keys -t rp2350_controller:0.0 \
            "cd ${PROJECT_ROOT} && source ${ROS2_WS}/install/setup.bash && \
             ros2 launch controller_driver controller_driver.launch.py \
             i2c_device:=${I2C_DEVICE} i2c_address:=${I2C_ADDRESS} publish_rate_hz:=${PUBLISH_RATE}" \
            Enter
        
        # Monitor in bottom pane
        tmux send-keys -t rp2350_controller:0.1 \
            "cd ${PROJECT_ROOT} && source ${ROS2_WS}/install/setup.bash && \
             ros2 topic echo /controller/input" \
            Enter
        
        # Attach to session
        tmux attach-session -t rp2350_controller
        
    else
        # Fallback: launch driver only, show instructions
        log_warn "tmux not available. Launching driver only."
        log_info "Open another terminal and run:"
        log_info "  ros2 topic echo /controller/input"
        echo ""
        launch_driver
    fi
}

# Main function
main() {
    print_banner
    parse_args "$@"
    check_ros2_environment
    
    echo ""
    log_info "Launch Mode: ${LAUNCH_MODE}"
    echo ""
    
    case "${LAUNCH_MODE}" in
        full)
            check_i2c_connection
            echo ""
            launch_full
            ;;
        driver)
            check_i2c_connection
            echo ""
            launch_driver
            ;;
        monitor)
            monitor_topics
            ;;
        test)
            run_diagnostics
            ;;
        *)
            log_error "Unknown mode: ${LAUNCH_MODE}"
            exit 1
            ;;
    esac
}

# Trap Ctrl+C for cleanup
cleanup() {
    echo ""
    log_info "Shutting down..."
    # Kill any background ros2 processes if needed
    # pkill -f "ros2 launch controller_driver" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Run main
main "$@"
exit $?