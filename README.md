# Force feedback manipulator firmware

This is a custom force feedback controller firmware for the RP2350 microcontroller with ROS2 integration.

## Hardware features

- Microcontroller: RP2350

- Input sensors:

  - Piezo sensor (12-bit ADC) for force/vibration detection
  - Analog joystick (X/Y axes, 12-bit ADC)
  - 3 digital buttons (active-low with pull-ups)

- Actuator interface: UART (9600 baud) for motor control

- Communication: I2C slave interface (400kHz Fast Mode, address 0x08)

## Software Architecture

- Firmware: Bare-metal C using Pico SDK

  - ADC reader with moving average filtering
  - I2C slave with IRQ-based TX/RX handling
  - UART motor command protocol (framed packets)

- ROS2 driver: C++ node running on host machine

  - Polls controller via I2C at configurable rate (default 50Hz)
  - Publishes sensor data to `/controller/input` topic
  - Subscribes to `/controller/motor_command` for actuator commands

## Protocol

- I2C Read: 8 bytes (controller data + XOR checksum)
- I2C Write: 4 bytes [START, speed, dir+enable, END]

## Build

- Firmware compiles to .uf2 for drag-and-drop flashing
- ROS2 packages build with colcon
- Automated build/flash scripts included
