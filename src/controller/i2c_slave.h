#pragma once

#include "config.h"
#include "pico/critical_section.h"

// Initialize I2C slave interface with IRQ handling
void i2c_slave_init(void);

// Prepare response buffer for next host read request
// Thread-safe: can be called from main loop while IRQ handles TX
void i2c_slave_prepare_response(const controller_input_t *input);

// Retrieve pending motor command from host (if available)
// Returns true if valid command was received and parsed
bool i2c_slave_get_command(motor_command_t *cmd);

// Optional: Get I2C error status for diagnostics
uint32_t i2c_slave_get_error_flags(void);

// Optional: Reset I2C state machine (recover from bus errors)
void i2c_slave_reset(void);