#include "rclcpp/rclcpp.hpp"
#include "controller_msgs/msg/controller_input.hpp"
#include "controller_msgs/msg/motor_command.hpp"
#include <linux/i2c-dev.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstring>

class ControllerDriver : public rclcpp::Node {
public:
    ControllerDriver() 
    : Node("controller_driver"),
      i2c_fd_(-1),
      i2c_address_(0x08)
    {
        // Declare parameters
        this->declare_parameter<std::string>("i2c_device", "/dev/i2c-1");
        this->declare_parameter<int>("i2c_address", 0x08);
        this->declare_parameter<int>("publish_rate_hz", 50);
        
        // Initialize I2C
        init_i2c();
        
        // Create publishers/subscribers
        input_pub_ = this->create_publisher<controller_msgs::msg::ControllerInput>(
            "controller/input", 10);
        command_sub_ = this->create_subscription<controller_msgs::msg::MotorCommand>(
            "controller/motor_command", 10,
            [this](const controller_msgs::msg::MotorCommand::SharedPtr msg) {
                send_motor_command(msg);
            });
        
        // Timer for periodic input polling
        auto period = std::chrono::milliseconds(
            1000 / this->get_parameter("publish_rate_hz").as_int());
        timer_ = this->create_wall_timer(period, 
            std::bind(&ControllerDriver::poll_controller, this));
        
        RCLCPP_INFO(this->get_logger(), "Controller driver initialized");
    }

private:
    void init_i2c() {
        std::string device = this->get_parameter("i2c_device").as_string();
        i2c_address_ = static_cast<uint8_t>(
            this->get_parameter("i2c_address").as_int());
        
        i2c_fd_ = open(device.c_str(), O_RDWR);
        if (i2c_fd_ < 0) {
            RCLCPP_ERROR(this->get_logger(), "Failed to open I2C device: %s", device.c_str());
            return;
        }
        
        if (ioctl(i2c_fd_, I2C_SLAVE, i2c_address_) < 0) {
            RCLCPP_ERROR(this->get_logger(), "Failed to acquire I2C bus access");
            close(i2c_fd_);
            i2c_fd_ = -1;
            return;
        }
        
        RCLCPP_INFO(this->get_logger(), "I2C connected to 0x%02X on %s", 
                   i2c_address_, device.c_str());
    }
    
    void poll_controller() {
        if (i2c_fd_ < 0) return;
        
        controller_msgs::msg::ControllerInput msg;
        msg.stamp = this->now();
        
        // Request data from RP2350
        uint8_t buffer[8];
        if (read(i2c_fd_, buffer, sizeof(buffer)) == sizeof(buffer)) {
            // Validate checksum (XOR of first 7 bytes)
            uint8_t checksum = 0;
            for (int i = 0; i < 7; i++) checksum ^= buffer[i];
            
            if (checksum == buffer[7]) {
                msg.buttons = buffer[0];  // buttons is 1st byte
                msg.piezo_value = (buffer[2] << 8) | buffer[3];
                msg.joystick_x = (buffer[4] << 8) | buffer[5];
                msg.joystick_y = (buffer[6] << 8) | buffer[7];
                
                msg.joystick_x_norm = (static_cast<float>(msg.joystick_x) / 4095.0f) * 2.0f - 1.0f;
                msg.joystick_y_norm = (static_cast<float>(msg.joystick_y) / 4095.0f) * 2.0f - 1.0f;
                msg.piezo_normalized = static_cast<float>(msg.piezo_value) / 4095.0f;
                
                input_pub_->publish(msg);
            } else {
                RCLCPP_WARN_THROTTLE(this->get_logger(), 
                    *this->get_clock(), 5000, "I2C checksum mismatch");
            }
        }
    }
    
    void send_motor_command(const controller_msgs::msg::MotorCommand::SharedPtr cmd) {
        if (i2c_fd_ < 0) return;
        
        uint8_t buffer[5] = {
            0xAA,
            cmd->speed,
            static_cast<uint8_t>(cmd->direction | (cmd->enable ? 0x02 : 0x00)),
            0x55
        };
        
        if (write(i2c_fd_, buffer, sizeof(buffer)) != sizeof(buffer)) {
            RCLCPP_WARN(this->get_logger(), "Failed to send motor command");
        }
    }
    
    // Member variables
    rclcpp::Publisher<controller_msgs::msg::ControllerInput>::SharedPtr input_pub_;
    rclcpp::Subscription<controller_msgs::msg::MotorCommand>::SharedPtr command_sub_;
    rclcpp::TimerBase::SharedPtr timer_;
    
    int i2c_fd_;
    uint8_t i2c_address_;
};

int main(int argc, char * argv[]) {
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ControllerDriver>());
    rclcpp::shutdown();
    return 0;
}