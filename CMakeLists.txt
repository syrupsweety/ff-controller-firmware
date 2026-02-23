cmake_minimum_required(VERSION 3.13)

include(pico_sdk_import.cmake)

project(rp2350_controller C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

add_executable(${PROJECT_NAME}
    src/main.c
    src/controller/controller.c
    src/controller/i2c_slave.c
    src/controller/adc_reader.c
    src/controller/uart_motor.c
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    pico_stdlib
    hardware_adc
    hardware_gpio
    hardware_i2c
    hardware_irq
    hardware_uart
    hardware_sync
)

# Enable USB/UART output for debugging
pico_enable_stdio_usb(${PROJECT_NAME} 1)
pico_enable_stdio_uart(${PROJECT_NAME} 0)

# Create map/bin/hex file
pico_add_extra_outputs(${PROJECT_NAME})

target_compile_definitions(${PROJECT_NAME} PRIVATE
    PICO_RP2350=1
    # PICO_DEFAULT_UART=0
    # PICO_DEFAULT_UART_TX_PIN=16
    # PICO_DEFAULT_UART_RX_PIN=17
)