#include "i2c_slave.h"
#include "config.h"
#include "controller.h"
#include "hardware/irq.h"
#include "pico/critical_section.h"

static uint8_t tx_buffer[I2C_TX_BUFFER_SIZE];
static uint8_t rx_buffer[I2C_RX_BUFFER_SIZE];
static volatile bool tx_data_ready = false;
static critical_section_t i2c_cs;

static void i2c_slave_irq_handler(void) {
    i2c_inst_t *i2c = CONTROLLER_I2C_PORT;
    
    // Handle RX
    if (i2c_get_irq_raw_status(i2c) & I2C_IC_RAW_INTR_STAT_RX_FULL_BITS) {
        while (i2c_get_rx_available(i2c)) {
            uint8_t data = i2c_read_byte_raw(i2c);
            static uint8_t rx_idx = 0;
            if (rx_idx < I2C_RX_BUFFER_SIZE) {
                rx_buffer[rx_idx++] = data;
            }
        }
        i2c_hw_t *hw = i2c_get_hw(i2c);
        hw->intr_stat; // Clear RX interrupt
    }
    
    // Handle TX
    if (i2c_get_irq_raw_status(i2c) & I2C_IC_RAW_INTR_STAT_TX_EMPTY_BITS) {
        if (tx_data_ready) {
            static uint8_t tx_idx = 0;
            if (tx_idx < sizeof(controller_input_t)) {
                i2c_write_byte_raw(i2c, tx_buffer[tx_idx++]);
            } else {
                tx_data_ready = false;
                tx_idx = 0;
                i2c_hw_t *hw = i2c_get_hw(i2c);
                hw->intr_mask &= ~I2C_IC_INTR_MASK_M_TX_EMPTY_BITS; // Disable TX empty IRQ
            }
        }
        i2c_hw_t *hw = i2c_get_hw(i2c);
        hw->intr_stat; // Clear TX interrupt
    }
}

void i2c_slave_init(void) {
    i2c_init(CONTROLLER_I2C_PORT, CONTROLLER_I2C_BAUDRATE);
    gpio_set_function(CONTROLLER_I2C_SDA_PIN, GPIO_FUNC_I2C);
    gpio_set_function(CONTROLLER_I2C_SCL_PIN, GPIO_FUNC_I2C);
    gpio_pull_up(CONTROLLER_I2C_SDA_PIN);
    gpio_pull_up(CONTROLLER_I2C_SCL_PIN);
    
    // Configure as slave
    i2c_set_slave_mode(CONTROLLER_I2C_PORT, true, CONTROLLER_I2C_ADDRESS);
    
    // Enable IRQs
    i2c_set_irq_enabled(CONTROLLER_I2C_PORT, I2C_RX_FULL_IRQ, true);
    i2c_set_irq_enabled(CONTROLLER_I2C_PORT, I2C_TX_EMPTY_IRQ, true);
    
    critical_section_init(&i2c_cs);
    
    // Register IRQ handler based on I2C port
#if CONTROLLER_I2C_PORT == i2c0
    irq_set_exclusive_handler(I2C0_IRQ, i2c_slave_irq_handler);
    irq_set_enabled(I2C0_IRQ, true);
#else
    irq_set_exclusive_handler(I2C1_IRQ, i2c_slave_irq_handler);
    irq_set_enabled(I2C1_IRQ, true);
#endif
}

void i2c_slave_prepare_response(const controller_input_t *input) {
    critical_section_enter_blocking(&i2c_cs);
    
    // Copy data to TX buffer
    memcpy(tx_buffer, input, sizeof(controller_input_t));
    
    // Calculate simple XOR checksum (7 bytes of data, checksum at byte 7)
    uint8_t checksum = 0;
    for (size_t i = 0; i < 7; i++) {
        checksum ^= tx_buffer[i];
    }
    tx_buffer[7] = checksum;
    
    tx_data_ready = true;
    
    // Re-enable TX empty IRQ for next transfer
    i2c_hw_t *hw = i2c_get_hw(CONTROLLER_I2C_PORT);
    hw->intr_mask |= I2C_IC_INTR_MASK_M_TX_EMPTY_BITS;
    
    critical_section_exit(&i2c_cs);
}

bool i2c_slave_get_command(motor_command_t *cmd) {
    critical_section_enter_blocking(&i2c_cs);
    
    // Simple protocol: expect 3-byte command in buffer
    if (rx_buffer[0] == PROTOCOL_START_BYTE && 
        rx_buffer[3] == PROTOCOL_END_BYTE) {
        
        cmd->speed = rx_buffer[1];
        cmd->direction = rx_buffer[2] & 0x01;
        cmd->enable = (rx_buffer[2] >> 1) & 0x01;
        
        // Clear buffer after processing
        memset(rx_buffer, 0, I2C_RX_BUFFER_SIZE);
        
        critical_section_exit(&i2c_cs);
        return true;
    }
    
    critical_section_exit(&i2c_cs);
    return false;
}