# Timestamp from host system
builtin_interfaces/Time stamp

# Button states (bitmask)
uint8 buttons  # bit0: BTN0, bit1: BTN1, bit2: JOY_BTN

# Analog sensor values (0-4095)
uint16 piezo_value
uint16 joystick_x
uint16 joystick_y

# Optional: calibrated/processed values
float32 joystick_x_norm  # -1.0 to 1.0
float32 joystick_y_norm  # -1.0 to 1.0
float32 piezo_normalized # 0.0 to 1.0