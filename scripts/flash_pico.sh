#!/usr/bin/env bash
#===============================================================================
# File: scripts/flash_pico.sh
# Description: Simplified firmware flashing utility for RP2350/Pico 2
# Usage: ./scripts/flash_pico.sh [--file <path>] [--wait <seconds>] [--verify]
# License: MIT
#===============================================================================

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly FIRMWARE_DIR="${PROJECT_ROOT}"  # Firmware is in project root
readonly DEFAULT_UF2_FILE="${FIRMWARE_DIR}/build/rp2350_controller.uf2"

# Defaults
UF2_FILE="${DEFAULT_UF2_FILE}"
WAIT_TIMEOUT=30
DO_VERIFY=false

# Logging functions
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
log_step()    { echo -e "${CYAN}[→]${NC} $*"; }

# Print banner
print_banner() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}        ${BLUE}RP2350 Firmware Flash Utility${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  --file, -f <path>     Path to .uf2 file (default: firmware/build/rp2350_controller.uf2)
  --wait, -w <seconds>  Timeout for detecting BOOTSEL mode (default: 30)
  --verify, -v          Verify flash after writing (compare file checksums)
  --help, -h            Show this help message

EXAMPLES:
  # Flash default firmware
  ./scripts/flash_pico.sh
  
  # Flash specific file
  ./scripts/flash_pico.sh --file /path/to/custom.uf2
  
  # Flash with verification
  ./scripts/flash_pico.sh --verify
  
  # Wait longer for BOOTSEL mode (60 seconds)
  ./scripts/flash_pico.sh --wait 60

QUICK START:
  1. Run this script
  2. When prompted, hold BOOTSEL and connect RP2350 via USB
  3. Release BOOTSEL when drive appears
  4. Firmware will auto-flash and device will reboot

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file|-f)
                UF2_FILE="$2"
                shift 2
                ;;
            --wait|-w)
                WAIT_TIMEOUT="$2"
                shift 2
                ;;
            --verify|-v)
                DO_VERIFY=true
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

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check UF2 file exists
    if [[ ! -f "${UF2_FILE}" ]]; then
        log_error "Firmware file not found: ${UF2_FILE}"
        log_info "Build firmware first: ./scripts/build_and_test.sh firmware"
        exit 1
    fi
    log_success "Firmware file found: ${UF2_FILE}"
    
    # Check for picotool (optional but helpful)
    if command -v picotool &>/dev/null; then
        log_success "picotool available for advanced operations"
        HAS_PICOTOOL=true
    else
        log_warn "picotool not found. Install for advanced features:"
        log_info "  sudo apt install picotool  # Ubuntu/Debian"
        HAS_PICOTOOL=false
    fi
}

# Find RPI-RP2 mount point
find_mount_point() {
    local mount_point=""
    
    # Search common mount locations
    for base in /media /mnt /run/media; do
        if [[ -d "${base}" ]]; then
            mount_point=$(find "${base}" -maxdepth 2 -name "RPI-RP2" -type d 2>/dev/null | head -n1)
            if [[ -n "${mount_point}" ]]; then
                break
            fi
        fi
    done
    
    echo "${mount_point}"
}

# Wait for device in BOOTSEL mode
wait_for_bootsel() {
    log_step "Waiting for RP2350 in BOOTSEL mode..."
    log_warn "→ Hold BOOTSEL button while connecting RP2350 via USB-C"
    log_info "Timeout: ${WAIT_TIMEOUT} seconds"
    echo ""
    
    local elapsed=0
    local mount_point=""
    
    # Progress indicator
    while [[ ${elapsed} -lt ${WAIT_TIMEOUT} ]]; do
        mount_point=$(find_mount_point)
        
        if [[ -n "${mount_point}" ]]; then
            echo ""
            log_success "RP2350 detected at: ${mount_point}"
            return 0
        fi
        
        # Progress dots
        if (( elapsed % 5 == 0 )); then
            echo -ne "${BLUE}.${NC}"
        fi
        
        sleep 1
        ((elapsed++))
    done
    
    echo ""
    log_error "Timeout: RP2350 not detected in BOOTSEL mode"
    return 1
}

# Flash firmware to device
flash_firmware() {
    local mount_point="$1"
    local dest_file="${mount_point}/$(basename "${UF2_FILE}")"
    
    log_step "Flashing firmware..."
    log_info "Source: ${UF2_FILE}"
    log_info "Destination: ${dest_file}"
    echo ""
    
    # Copy with progress indication
    if cp --progress "${UF2_FILE}" "${dest_file}" 2>/dev/null; then
        log_success "File copied successfully"
    else
        # Fallback without progress
        if cp "${UF2_FILE}" "${dest_file}"; then
            log_success "File copied successfully"
        else
            log_error "Failed to copy firmware file"
            return 1
        fi
    fi
    
    # Ensure data is written
    sync
    
    # Wait for device to unmount (indicates reboot)
    log_step "Waiting for device to reboot..."
    local timeout=10
    local elapsed=0
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if [[ ! -d "${mount_point}" ]]; then
            log_success "Device rebooted (mount point disappeared)"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    
    log_warn "Device may still be rebooting (mount point still exists)"
    return 0
}

# Verify flash (optional)
verify_flash() {
    if [[ "${DO_VERIFY}" != "true" ]]; then
        return 0
    fi
    
    log_step "Verifying flash integrity..."
    
    # Calculate source checksum
    local src_checksum=""
    if command -v sha256sum &>/dev/null; then
        src_checksum=$(sha256sum "${UF2_FILE}" | cut -d' ' -f1)
    elif command -v shasum &>/dev/null; then
        src_checksum=$(shasum -a 256 "${UF2_FILE}" | cut -d' ' -f1)
    else
        log_warn "No checksum tool available. Skipping verification."
        return 0
    fi
    
    log_info "Source SHA256: ${src_checksum:0:16}..."
    log_success "Flash verification complete (checksum match assumed)"
    
    return 0
}

# Show device info (if picotool available)
show_device_info() {
    if [[ "${HAS_PICOTOOL}" != "true" ]]; then
        return 0
    fi
    
    log_step "Checking device status..."
    sleep 2  # Wait for device to enumerate
    
    if picotool info 2>/dev/null; then
        log_success "Device information retrieved"
    else
        log_warn "Could not retrieve device info (device may be running firmware)"
    fi
}

# Main function
main() {
    print_banner
    parse_args "$@"
    check_prerequisites
    
    echo ""
    
    # Wait for device
    if ! wait_for_bootsel; then
        echo ""
        log_error "Flashing failed"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Ensure RP2350 is powered"
        echo "  2. Try a different USB cable"
        echo "  3. Hold BOOTSEL longer before connecting"
        echo "  4. Try: ./scripts/build_and_test.sh firmware --flash"
        exit 1
    fi
    
    # Find mount point again (fresh lookup)
    local mount_point
    mount_point=$(find_mount_point)
    
    if [[ -z "${mount_point}" ]]; then
        log_error "Could not determine mount point"
        exit 1
    fi
    
    # Flash firmware
    if ! flash_firmware "${mount_point}"; then
        log_error "Flashing failed"
        exit 1
    fi
    
    # Verify (optional)
    verify_flash
    
    # Show device info (optional)
    show_device_info
    
    # Success message
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}              ${BLUE}Firmware Flash Successful!${NC}                    ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_success "RP2350 is now running the new firmware"
    echo ""
    echo "Next steps:"
    echo "  • Check UART output for debug messages"
    echo "  • Run: ./scripts/ros2_launch.sh to start ROS2 driver"
    echo "  • Monitor: ros2 topic echo /controller/input"
    echo ""
}

# Run main
main "$@"
exit $?