cmake_minimum_required(VERSION 3.16)
project(open-rdp-client VERSION 0.3.0 LANGUAGES CXX)

set(OPEN_RDP_PLATFORM "linux" CACHE STRING "Frontend: linux or ubuntu-touch")
set_property(CACHE OPEN_RDP_PLATFORM PROPERTY STRINGS linux ubuntu-touch)
if(NOT OPEN_RDP_PLATFORM MATCHES "^(linux|ubuntu-touch)$")
    message(FATAL_ERROR "OPEN_RDP_PLATFORM must be linux or ubuntu-touch")
endif()
if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(FATAL_ERROR "Build on Linux, or use Clickable for Ubuntu Touch")
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
include(CTest)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
if(OPEN_RDP_PLATFORM STREQUAL "ubuntu-touch")
    set(RUST_FEATURE ubuntu-touch)
    find_package(Qt5 5.15 REQUIRED COMPONENTS Core Gui Qml Quick Multimedia)
    set(QT_PACKAGE Qt5)
else()
    set(RUST_FEATURE linux-desktop)
    find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Multimedia Svg)
    set(QT_PACKAGE Qt6)
endif()
if(NOT RUST_TARGET)
    if(OPEN_RDP_PLATFORM STREQUAL "ubuntu-touch" AND DEFINED ENV{ARCH_RUST})
        set(RUST_TARGET "$ENV{ARCH_RUST}")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
        set(RUST_TARGET aarch64-unknown-linux-gnu)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
        set(RUST_TARGET armv7-unknown-linux-gnueabihf)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
        set(RUST_TARGET x86_64-unknown-linux-gnu)
    else()
        message(FATAL_ERROR "Unsupported Rust architecture; set RUST_TARGET explicitly")
    endif()
endif()
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(RUST_PROFILE debug)
else()
    set(RUST_PROFILE release)
endif()
set(SHARED_DIR "${CMAKE_SOURCE_DIR}/open-rdp-client")
set(RUST_TARGET_DIR "${CMAKE_BINARY_DIR}/cargo-target")
set(RUST_STATIC_LIB "${RUST_TARGET_DIR}/${RUST_TARGET}/${RUST_PROFILE}/librdp_client_ut.a")
file(GLOB_RECURSE RUST_SOURCES CONFIGURE_DEPENDS
    "${SHARED_DIR}/src/*.rs" "${CMAKE_SOURCE_DIR}/vendor/ironrdp-session/src/*.rs")
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/rust-build-config.txt"
    CONTENT "${RUST_FEATURE}\n${RUST_PROFILE}\n${CMAKE_CXX_COMPILER}\n${RUST_TARGET}\n")
add_custom_command(OUTPUT ${RUST_STATIC_LIB}
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/build-rust.py
            ${RUST_TARGET_DIR} ${RUST_TARGET} ${CMAKE_CXX_COMPILER} ${RUST_FEATURE} ${RUST_PROFILE}
    COMMAND ${CMAKE_COMMAND} -E touch ${RUST_STATIC_LIB}
    DEPENDS ${RUST_SOURCES} ${CMAKE_SOURCE_DIR}/Cargo.toml ${CMAKE_SOURCE_DIR}/Cargo.lock
        ${SHARED_DIR}/Cargo.toml ${SHARED_DIR}/sentry.json ${SHARED_DIR}/resources.qrc
        ${CMAKE_SOURCE_DIR}/vendor/ironrdp-session/Cargo.toml
        ${CMAKE_SOURCE_DIR}/linux/resources.qrc ${CMAKE_SOURCE_DIR}/ubuntu-touch/resources.qrc
        ${CMAKE_SOURCE_DIR}/scripts/build-rust.py ${CMAKE_BINARY_DIR}/rust-build-config.txt
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    USES_TERMINAL
    VERBATIM
)
add_custom_target(rust-rdp-backend DEPENDS ${RUST_STATIC_LIB})
add_library(rdp-qt STATIC
    ${SHARED_DIR}/qt/RdpBridge.cpp ${SHARED_DIR}/qt/RdpBridge.h
    ${SHARED_DIR}/qt/RdpCanvasItem.cpp ${SHARED_DIR}/qt/RdpCanvasItem.h)
add_dependencies(rdp-qt rust-rdp-backend)
target_include_directories(rdp-qt PUBLIC ${SHARED_DIR}/qt)
target_link_options(rdp-qt INTERFACE -Wl,--gc-sections)
target_link_libraries(rdp-qt PUBLIC ${RUST_STATIC_LIB}
    ${QT_PACKAGE}::Core ${QT_PACKAGE}::Gui ${QT_PACKAGE}::Qml
    ${QT_PACKAGE}::Quick ${QT_PACKAGE}::Multimedia z pthread dl m)
add_subdirectory(${OPEN_RDP_PLATFORM})
if(OPEN_RDP_PLATFORM STREQUAL "linux")
    include(linux/packaging/Package.cmake)
    include(CPack)
endif()
