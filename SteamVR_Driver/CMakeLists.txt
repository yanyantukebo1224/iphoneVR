cmake_minimum_required(VERSION 3.15)
project(driver_iphonevr CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(driver_iphonevr SHARED
    src/driver_main.cpp
    src/hmd_device_driver.cpp
    src/hand_controller_driver.cpp
    src/udp_receiver.cpp
)

target_include_directories(driver_iphonevr PRIVATE src)

if(WIN32)
    target_link_libraries(driver_iphonevr PRIVATE ws2_32)
    set_target_properties(driver_iphonevr PROPERTIES
        OUTPUT_NAME "driver_driver_iphonevr"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/driver_iphonevr/bin/win64"
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/driver_iphonevr/bin/win64"
    )
endif()
