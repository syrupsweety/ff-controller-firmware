from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

def generate_launch_description():
    i2c_device_arg = DeclareLaunchArgument(
        'i2c_device',
        default_value='/dev/i2c-1',
        description='I2C device path for controller communication'
    )
    
    i2c_address_arg = DeclareLaunchArgument(
        'i2c_address',
        default_value='8',  # 0x08
        description='I2C address of RP2350 controller (decimal)'
    )
    
    publish_rate_arg = DeclareLaunchArgument(
        'publish_rate_hz',
        default_value='50',
        description='Input publishing rate in Hz'
    )

    controller_node = Node(
        package='controller_driver',
        executable='controller_driver_node',
        name='controller_driver',
        output='screen',
        parameters=[{
            'i2c_device': LaunchConfiguration('i2c_device'),
            'i2c_address': LaunchConfiguration('i2c_address'),
            'publish_rate_hz': LaunchConfiguration('publish_rate_hz'),
            'joystick_deadzone': 0.05,
            'piezo_threshold': 200
        }],
        remappings=[
            ('/controller/input', '/sensors/controller'),
            ('/controller/motor_command', '/actuators/motor_cmd')
        ]
    )

    return LaunchDescription([
        i2c_device_arg,
        i2c_address_arg,
        publish_rate_arg,
        controller_node
    ])