#include "uart_motor.h"
#include "config.h"
#include "hardware/uart.h"
#include "hardware/gpio.h"
#include "pico/stdlib.h"

void uart_motor_init(void) {
    uart_init(MOTOR_UART_PORT, MOTOR_UART_BAUDRATE);
    
    gpio_set_function(MOTOR_UART_TX_PIN, GPIO_FUNC_UART);
    gpio_set_function(MOTOR_UART_RX_PIN, GPIO_FUNC_UART);
    
    // Configure UART: 8N1
    uart_set_format(MOTOR_UART_PORT, 8, 1, UART_PARITY_NONE);
    uart_set_hw_flow(MOTOR_UART_PORT, false, false);
    uart_set_fifo_enabled(MOTOR_UART_PORT, true);
    
    // Clear any residual data
    uart_motor_flush();
}

void uart_motor_flush(void) {
    // Clear RX FIFO
    while (uart_is_readable(MOTOR_UART_PORT)) {
        uart_getc(MOTOR_UART_PORT);
    }
    // Clear TX FIFO
    while (uart_is_writable(MOTOR_UART_PORT)) {
        // Wait for TX to complete
    }
}

bool uart_motor_send_command(const motor_command_t *cmd) {
    if (!cmd) return false;
    
    // Build framed packet: [START, SPEED, DIR+EN, END]
    uint8_t packet[PROTOCOL_TOTAL_SIZE];
    packet[0] = PROTOCOL_START_BYTE;
    packet[1] = cmd->speed;
    packet[2] = (cmd->direction & 0x01) | ((cmd->enable ? 1 : 0) << 1);
    packet[3] = PROTOCOL_END_BYTE;
    
    // Send with timeout
    absolute_time_t timeout = make_timeout_time_ms(10);
    for (size_t i = 0; i < PROTOCOL_TOTAL_SIZE; i++) {
        if (absolute_time_diff_us(get_absolute_time(), timeout) < 0) {
            return false;  // Timeout
        }
        uart_putc_raw(MOTOR_UART_PORT, packet[i]);
    }
    
    uart_tx_wait_blocking(MOTOR_UART_PORT);
    return true;
}

bool uart_motor_check_ack(uint32_t timeout_ms) {
    absolute_time_t timeout = make_timeout_time_ms(timeout_ms);
    
    while (absolute_time_diff_us(get_absolute_time(), timeout) >= 0) {
        if (uart_is_readable(MOTOR_UART_PORT)) {
            uint8_t ack = uart_getc(MOTOR_UART_PORT);
            return (ack == 0xAC);  // Example ACK byte
        }
        sleep_us(100);
    }
    return false;
}