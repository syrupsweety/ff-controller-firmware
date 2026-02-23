#pragma once

#include "config.h"

// Initialize GPIO pins for controller inputs
void controller_gpio_init(void);

// Read all controller inputs into structured data
// Call at fixed interval (e.g., 50-100Hz)
void controller_read_inputs(controller_input_t *input);

// Process and send motor command to actuator
void controller_process_command(const motor_command_t *cmd);

// Optional: Calibrate joystick center values (call once at startup)
void controller_calibrate_joystick(uint16_t *center_x, uint16_t *center_y);

// Optional: Get firmware version string
const char* controller_get_version(void);