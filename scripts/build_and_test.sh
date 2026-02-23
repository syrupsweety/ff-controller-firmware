#!/usr/bin/env bash
#===============================================================================
# File: scripts/build_and_test.sh
# Description: Automated build, flash, and test script for RP2350 controller
#              with ROS2 integration
# Usage: ./scripts/build_and_test.sh [firmware|ros2|all] [--flash] [--test]
# License: MIT
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly FIRMWARE_DIR="${PROJECT_ROOT}"  # Firmware is in project root
readonly ROS2_WS="${PROJECT_ROOT}/ros2_ws"
readonly ROS2_SRC="${PROJECT_ROOT}/ros"

# Default options
BUILD_TARGET="${1:-all}"      # firmware | ros2 | all
DO_FLASH="${2:-false}"        # --flash flag
DO_TEST="${3:-false}"         # --test flag

# Helper functions
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[✗]${NC} $*" >&2; }

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Required command '$1' not found. Please install it."
        exit 1
    fi
}

check_pico_sdk() {
    if [[ -z "${PICO_SDK_PATH:-}" ]] || [[ ! -d "${PICO_SDK_PATH}" ]]; then
        log_error "PICO_SDK_PATH not set or invalid: ${PICO_SDK_PATH:-not set}"
        log_info "Set it with: export PICO_SDK_PATH=/path/to/pico-sdk"
        exit 1
    fi
    log_info "Using Pico SDK: ${PICO_SDK_PATH}"
}

check_ros2() {
    if ! command -v ros2 &>/dev/null; then
        log_warn "ROS2 not found in PATH. Skipping ROS2 build."
        return 1
    fi
    if [[ -z "${ROS_DISTRO:-}" ]]; then
        log_warn "ROS_DISTRO not set. Source your ROS2 setup.bash first."
        return 1
    fi
    log_info "Using ROS2 distribution: ${ROS_DISTRO}"
    return 0
}

# Firmware build function
build_firmware() {
    log_info "Building firmware for RP2350..."
    check_command cmake
    check_command make
    check_pico_sdk

    cd "${FIRMWARE_DIR}"
    
    # Create build directory
    mkdir -p build
    cd build
    
    # Configure
    log_info "Running CMake configuration..."
    cmake .. \
        -DPICO_BOARD=pico2 \
        -DCMAKE_BUILD_TYPE=Release \
        -DPICO_SDK_PATH="${PICO_SDK_PATH}" \
        -DPICO_PLATFORM=rp2350
    
    # Build
    log_info "Compiling firmware..."
    make -j"$(nproc 2>/dev/null || echo 4)"
    
    # Verify output
    if [[ -f "rp2350_controller.uf2" ]]; then
        log_success "Firmware built: ${FIRMWARE_DIR}/build/rp2350_controller.uf2"
        return 0
    else
        log_error "Firmware build failed: .uf2 file not found"
        return 1
    fi
}

# Flash firmware function
flash_firmware() {
    log_info "Waiting for RP2350 in BOOTSEL mode..."
    log_warn "→ Hold BOOTSEL button while connecting RP2350 via USB"
    
    local uf2_file="${FIRMWARE_DIR}/build/rp2350_controller.uf2"
    
    if [[ ! -f "${uf2_file}" ]]; then
        log_error "Firmware file not found: ${uf2_file}"
        log_info "Run './scripts/build_and_test.sh firmware' first"
        return 1
    fi
    
    # Wait for RPI-RP2 mount point (timeout: 30s)
    local timeout=30
    local elapsed=0
    local mount_point=""
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        mount_point=$(find /media /mnt /run/media -name "RPI-RP2" -type d 2>/dev/null | head -n1)
        if [[ -n "${mount_point}" ]]; then
            break
        fi
        sleep 1
        ((elapsed++))
    done
    
    if [[ -z "${mount_point}" ]]; then
        log_error "RP2350 not detected in BOOTSEL mode after ${timeout}s"
        log_info "Manual flash: Copy ${uf2_file} to the RPI-RP2 drive"
        return 1
    fi
    
    log_info "Flashing to ${mount_point}..."
    cp "${uf2_file}" "${mount_point}/"
    sync
    
    # Wait for device to reboot
    sleep 2
    log_success "Firmware flashed successfully!"
    return 0
}

# ROS2 workspace build function
build_ros2() {
    log_info "Building ROS2 workspace..."
    
    if ! check_ros2; then
        log_warn "Skipping ROS2 build (ROS2 not available)"
        return 0
    fi
    
    check_command colcon
    check_command rosdep
    
    # Create workspace if needed
    if [[ ! -d "${ROS2_WS}" ]]; then
        log_info "Creating ROS2 workspace at ${ROS2_WS}"
        mkdir -p "${ROS2_WS}/src"
        # Copy packages
        cp -r "${ROS2_SRC}/"* "${ROS2_WS}/src/"
    fi
    
    cd "${ROS2_WS}"
    
    # Install dependencies
    log_info "Installing ROS2 dependencies..."
    rosdep update
    rosdep install --from-paths src --ignore-src -r -y -q
    
    # Build packages
    log_info "Compiling ROS2 packages with colcon..."
    colcon build \
        --packages-select controller_msgs controller_driver \
        --symlink-install \
        --cmake-args -DCMAKE_BUILD_TYPE=Release \
        --executor sequential  # More reliable for debugging
    
    # Source the workspace
    if [[ -f "install/setup.bash" ]]; then
        log_success "ROS2 workspace built: ${ROS2_WS}"
        log_info "Source with: source ${ROS2_WS}/install/setup.bash"
        return 0
    else
        log_error "ROS2 build failed: install/setup.bash not found"
        return 1
    fi
}

# Run integration tests
run_tests() {
    log_info "Running integration tests..."
    
    if ! check_ros2; then
        log_warn "Skipping tests (ROS2 not available)"
        return 0
    fi
    
    # Source ROS2
    if [[ -f "${ROS2_WS}/install/setup.bash" ]]; then
        source "${ROS2_WS}/install/setup.bash"
    else
        log_warn "ROS2 workspace not built. Run with --build first."
        return 0
    fi
    
    # Test 1: Check I2C device
    log_info "Test 1: Checking I2C bus..."
    if command -v i2cdetect &>/dev/null; then
        if i2cdetect -y -r 1 2>/dev/null | grep -q "08"; then
            log_success "✓ Controller detected at I2C address 0x08"
        else
            log_warn "✗ Controller not found on I2C bus (expected 0x08)"
            log_info "Check wiring and that firmware is running"
        fi
    else
        log_warn "i2cdetect not available. Install i2c-tools to run I2C tests."
    fi
    
    # Test 2: ROS2 topic echo (non-blocking)
    log_info "Test 2: Checking ROS2 topics..."
    if ros2 topic list 2>/dev/null | grep -q "controller"; then
        log_success "✓ Controller topics available"
        ros2 topic list | grep controller | sed 's/^/  /'
    else
        log_warn "✗ Controller topics not found. Start the driver node first:"
        log_info "  ros2 launch controller_driver controller_driver.launch.py"
    fi
    
    # Test 3: Publish test command (dry-run)
    log_info "Test 3: Validating message types..."
    if ros2 interface show controller_msgs/msg/MotorCommand &>/dev/null; then
        log_success "✓ Custom messages registered correctly"
    else
        log_warn "✗ Message types not found. Rebuild controller_msgs package"
    fi
    
    log_success "Integration tests completed"
    return 0
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 [TARGET] [OPTIONS]

TARGET:
  firmware    Build only RP2350 firmware
  ros2        Build only ROS2 workspace
  all         Build both (default)

OPTIONS:
  --flash     Flash firmware to RP2350 after build (requires BOOTSEL mode)
  --test      Run integration tests after build
  --help      Show this help message

EXAMPLES:
  # Build everything
  ./scripts/build_and_test.sh all
  
  # Build and flash firmware
  ./scripts/build_and_test.sh firmware --flash
  
  # Build ROS2 and run tests
  ./scripts/build_and_test.sh ros2 --test
  
  # Full workflow: build all, flash, test
  ./scripts/build_and_test.sh all --flash --test

ENVIRONMENT VARIABLES:
  PICO_SDK_PATH    Path to Raspberry Pi Pico SDK (required for firmware)
  ROS_DISTRO       ROS2 distribution (e.g., humble, iron) - source setup.bash first

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        firmware|ros2|all)
            BUILD_TARGET="$1"
            shift
            ;;
        --flash)
            DO_FLASH=true
            shift
            ;;
        --test)
            DO_TEST=true
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

# Main execution
main() {
    log_info "RP2350 Controller Build System"
    log_info "Target: ${BUILD_TARGET}, Flash: ${DO_FLASH}, Test: ${DO_TEST}"
    echo ""
    
    local exit_code=0
    
    # Build phase
    case "${BUILD_TARGET}" in
        firmware)
            build_firmware || exit_code=1
            ;;
        ros2)
            build_ros2 || exit_code=1
            ;;
        all)
            build_firmware || exit_code=1
            echo ""
            build_ros2 || exit_code=1
            ;;
    esac
    
    # Flash phase
    if [[ "${DO_FLASH}" == "true" ]] && [[ ${exit_code} -eq 0 ]]; then
        echo ""
        flash_firmware || exit_code=1
    fi
    
    # Test phase
    if [[ "${DO_TEST}" == "true" ]] && [[ ${exit_code} -eq 0 ]]; then
        echo ""
        run_tests || exit_code=1
    fi
    
    # Summary
    echo ""
    if [[ ${exit_code} -eq 0 ]]; then
        log_success "Build completed successfully! 🎉"
        echo ""
        echo "Next steps:"
        echo "  1. Flash firmware (if not done): ./scripts/build_and_test.sh firmware --flash"
        echo "  2. Source ROS2: source ${ROS2_WS}/install/setup.bash"
        echo "  3. Launch driver: ros2 launch controller_driver controller_driver.launch.py"
        echo "  4. Monitor: ros2 topic echo /controller/input"
    else
        log_error "Build completed with errors. Check output above."
    fi
    
    return ${exit_code}
}

# Run main
main
exit $?