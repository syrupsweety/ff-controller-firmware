#pragma once

#include "pico/stdlib.h"
#include "hardware/adc.h"
#include "hardware/i2c.h"
#include "hardware/uart.h"

// ===== I2C Configuration =====
#define CONTROLLER_I2C_PORT         i2c0
#define CONTROLLER_I2C_SDA_PIN      4
#define CONTROLLER_I2C_SCL_PIN      5
#define CONTROLLER_I2C_ADDRESS      0x08
#define CONTROLLER_I2C_BAUDRATE     400000  // 400 kHz Fast Mode

// ===== GPIO Pin Assignments =====
#define BTN_0_PIN                   9
#define BTN_1_PIN                   8
#define BTN_JOY_PIN                 3
#define PIEZO_ADC_PIN               0  // ADC0 -> GPIO26
#define JOY_X_ADC_PIN               2  // ADC2 -> GPIO28
#define JOY_Y_ADC_PIN               1  // ADC1 -> GPIO27

// ===== UART Motor Interface =====
#define MOTOR_UART_PORT             uart1
#define MOTOR_UART_TX_PIN           12
#define MOTOR_UART_RX_PIN           13
#define MOTOR_UART_BAUDRATE         9600
#define MOTOR_UART_ID               1

// ===== ADC Configuration =====
#define ADC_RESOLUTION_BITS         12
#define ADC_MAX_VALUE               ((1 << ADC_RESOLUTION_BITS) - 1)
#define ADC_SAMPLE_INTERVAL_US      1000

// ===== I2C Protocol Definition =====
#define I2C_RX_BUFFER_SIZE          16
#define I2C_TX_BUFFER_SIZE          16
#define PROTOCOL_START_BYTE         0xAA
#define PROTOCOL_END_BYTE           0x55
#define PROTOCOL_HEADER_SIZE        2
#define PROTOCOL_PAYLOAD_SIZE       3
#define PROTOCOL_FOOTER_SIZE        1
#define PROTOCOL_TOTAL_SIZE         (PROTOCOL_HEADER_SIZE + PROTOCOL_PAYLOAD_SIZE + PROTOCOL_FOOTER_SIZE)

// ===== Data Structures =====
typedef struct __attribute__((packed)) {
    uint8_t speed;      // 0-255
    uint8_t direction;  // 0=CCW, 1=CW
    uint8_t enable;     // 0=disable, 1=enable
} motor_command_t;

typedef struct __attribute__((packed)) {
    uint8_t buttons;            // Bitmask: bit0=BTN0, bit1=BTN1, bit2=JOY_BTN
    uint8_t reserved;           // Padding for alignment
    uint16_t piezo_value;       // 0-4095
    uint16_t joystick_x;        // 0-4095
    uint16_t joystick_y;        // 0-4095
    uint8_t checksum;           // Simple XOR checksum
} controller_input_t;
