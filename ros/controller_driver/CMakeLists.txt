cmake_minimum_required(VERSION 3.8)
project(controller_driver)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(controller_msgs REQUIRED)
find_package(builtin_interfaces REQUIRED)

# I2C access requires linking against system libraries
find_library(I2C_LIB i2c)

add_executable(controller_driver_node src/controller_driver_node.cpp)
target_include_directories(controller_driver_node PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:include>)
target_compile_features(controller_driver_node PUBLIC c_std_99 cxx_std_17)

target_link_libraries(controller_driver_node
  ${I2C_LIB}
)

ament_target_dependencies(controller_driver_node
  rclcpp
  controller_msgs
  builtin_interfaces
)

install(TARGETS controller_driver_node
  DESTINATION lib/${PROJECT_NAME})

install(DIRECTORY launch
  DESTINATION share/${PROJECT_NAME})

ament_package()