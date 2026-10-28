cmake_minimum_required(VERSION 3.16)
project(rdp-client-ut VERSION 0.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt5 5.15 REQUIRED COMPONENTS Core Gui Qml Quick Multimedia)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

if(DEFINED ENV{ARCH_RUST})
    set(RUST_TARGET "$ENV{ARCH_RUST}")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(RUST_TARGET aarch64-unknown-linux-gnu)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
    set(RUST_TARGET armv7-unknown-linux-gnueabihf)
else()
    set(RUST_TARGET x86_64-unknown-linux-gnu)
endif()

set(RUST_TARGET_DIR "${CMAKE_SOURCE_DIR}/build/cargo-target")
set(RUST_STATIC_LIB "${RUST_TARGET_DIR}/${RUST_TARGET}/release/librdp_client_ut.a")

add_custom_target(rust-rdp-backend ALL
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/build-rust.py
            ${RUST_TARGET_DIR} ${RUST_TARGET} ${CMAKE_CXX_COMPILER}
    BYPRODUCTS ${RUST_STATIC_LIB}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    USES_TERMINAL
)

add_executable(rdp-client-ut
    qt/main.cpp
    qt/RdpBridge.cpp
    qt/RdpBridge.h
    qt/RdpCanvasItem.cpp
    qt/RdpCanvasItem.h
    resources.qrc
)

add_dependencies(rdp-client-ut rust-rdp-backend)
target_include_directories(rdp-client-ut PRIVATE qt)
target_link_options(rdp-client-ut PRIVATE -Wl,--gc-sections -Wl,-s)
target_link_libraries(rdp-client-ut PRIVATE
    ${RUST_STATIC_LIB}
    Qt5::Core
    Qt5::Gui
    Qt5::Qml
    Qt5::Quick
    Qt5::Multimedia
    z
    pthread
    dl
    m
)

install(TARGETS rdp-client-ut RUNTIME DESTINATION .)
install(FILES manifest.json.in DESTINATION . RENAME manifest.json)
install(FILES rdp-client-ut.desktop.in DESTINATION . RENAME rdp-client-ut.desktop)
install(FILES rdp-client-ut.apparmor DESTINATION .)
install(FILES assets/logo.svg DESTINATION assets)
install(FILES LICENSE DESTINATION .)
