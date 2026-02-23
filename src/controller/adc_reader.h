#pragma once

#include "hardware/adc.h"
#include "pico/stdlib.h"

// Initialize ADC subsystem
void adc_reader_init(void);

// Read ADC channel (0-3) with optional averaging
// Returns value in range [0, 4095] for 12-bit resolution
uint16_t adc_reader_read(uint8_t channel);

// Read ADC channel with moving average filter
// window_size: number of samples to average (1-16)
uint16_t adc_reader_read_filtered(uint8_t channel, uint8_t window_size);

// Get raw ADC value without any processing
uint16_t adc_reader_read_raw(uint8_t channel);