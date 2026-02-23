#include "adc_reader.h"
#include "config.h"
#include "hardware/adc.h"
#include "pico/stdlib.h"
#include "hardware/irq.h"

#define ADC_FIFO_DEPTH      8
#define ADC_MAX_CHANNEL     3

static bool adc_initialized = false;
static uint16_t adc_filters[ADC_MAX_CHANNEL + 1][16];
static uint8_t adc_filter_idx[ADC_MAX_CHANNEL + 1] = {0};
static uint8_t adc_filter_size[ADC_MAX_CHANNEL + 1] = {0};

void adc_reader_init(void) {
    if (adc_initialized) return;
    
    adc_init();
    adc_set_clkdiv(1);  // ~500kHz ADC clock (safe for 12-bit)
    adc_fifo_setup(false, false, 0, false, false);  // Disable FIFO for simple polling
    
    // Initialize filter buffers
    for (int ch = 0; ch <= ADC_MAX_CHANNEL; ch++) {
        for (int i = 0; i < 16; i++) {
            adc_filters[ch][i] = 0;
        }
        adc_filter_idx[ch] = 0;
        adc_filter_size[ch] = 0;
    }
    
    adc_initialized = true;
}

uint16_t adc_reader_read_raw(uint8_t channel) {
    if (channel > ADC_MAX_CHANNEL) return 0;
    
    adc_select_input(channel);
    return adc_read();  // Returns 0-4095 for 12-bit
}

uint16_t adc_reader_read(uint8_t channel) {
    return adc_reader_read_filtered(channel, 4);  // Default: 4-sample average
}

uint16_t adc_reader_read_filtered(uint8_t channel, uint8_t window_size) {
    if (channel > ADC_MAX_CHANNEL) return 0;
    if (window_size == 0 || window_size > 16) window_size = 4;
    
    // Read new sample
    uint16_t sample = adc_reader_read_raw(channel);
    
    // Circular buffer update
    uint8_t *idx = &adc_filter_idx[channel];
    uint16_t *filter = adc_filters[channel];
    
    filter[*idx] = sample;
    *idx = (*idx + 1) % window_size;
    
    // Track actual filled size
    if (adc_filter_size[channel] < window_size) {
        adc_filter_size[channel]++;
    }
    
    // Compute average
    uint32_t sum = 0;
    uint8_t count = adc_filter_size[channel];
    for (uint8_t i = 0; i < count; i++) {
        sum += filter[i];
    }
    
    return (uint16_t)(sum / count);
}