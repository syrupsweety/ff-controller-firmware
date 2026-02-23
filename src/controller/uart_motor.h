#pragma once

#include "config.h"
#include "hardware/uart.h"

// Initialize UART for motor communication
void uart_motor_init(void);

// Send motor command via UART with protocol framing
// Returns true on success, false on timeout/error
bool uart_motor_send_command(const motor_command_t *cmd);

// Check if motor acknowledged last command (optional)
bool uart_motor_check_ack(uint32_t timeout_ms);

// Flush UART buffers
void uart_motor_flush(void);