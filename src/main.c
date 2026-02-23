#include "pico/stdlib.h"
#include "hardware/adc.h"
#include "config.h"
#include "controller.h"
#include "i2c_slave.h"
#include "adc_reader.h"
#include "uart_motor.h"

int main(void) {
    // Standard Pico SDK initialization
    stdio_init_all();
    
    // Initialize hardware subsystems
    adc_init();
    adc_reader_init();
    controller_gpio_init();
    uart_motor_init();
    i2c_slave_init();
    
    printf("RP2350 Controller initialized @ 0x%02X\n", CONTROLLER_I2C_ADDRESS);
    
    controller_input_t input = {0};
    motor_command_t command = {0};
    
    while (true) {
        controller_read_inputs(&input);
        
        i2c_slave_prepare_response(&input);
        
        if (i2c_slave_get_command(&command)) {
            controller_process_command(&command);
        }
        
        sleep_us(1000);
    }
}