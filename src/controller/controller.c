#include "controller.h"
#include "config.h"
#include "adc_reader.h"
#include "uart_motor.h"
#include "hardware/gpio.h"

void controller_gpio_init(void) {
    // Button pins with pull-up
    const uint8_t btn_pins[] = {BTN_0_PIN, BTN_1_PIN, BTN_JOY_PIN};
    for (size_t i = 0; i < sizeof(btn_pins)/sizeof(btn_pins[0]); i++) {
        gpio_init(btn_pins[i]);
        gpio_set_dir(btn_pins[i], GPIO_IN);
        gpio_pull_up(btn_pins[i]);
    }
    
    // ADC pins
    adc_gpio_init(26 + PIEZO_ADC_PIN);   // GPIO26 = ADC0
    adc_gpio_init(26 + JOY_Y_ADC_PIN);   // GPIO27 = ADC1  
    adc_gpio_init(26 + JOY_X_ADC_PIN);   // GPIO28 = ADC2
}

void controller_read_inputs(controller_input_t *input) {
    // Read digital buttons (active-low with pullup)
    input->buttons = 0;
    if (!gpio_get(BTN_0_PIN)) input->buttons |= (1 << 0);
    if (!gpio_get(BTN_1_PIN)) input->buttons |= (1 << 1);
    if (!gpio_get(BTN_JOY_PIN)) input->buttons |= (1 << 2);
    
    // Read analog sensors
    input->piezo_value = adc_reader_read(PIEZO_ADC_PIN);
    input->joystick_x = adc_reader_read(JOY_X_ADC_PIN);
    input->joystick_y = adc_reader_read(JOY_Y_ADC_PIN);
}

void controller_process_command(const motor_command_t *cmd) {
    uart_motor_send_command(cmd);
}