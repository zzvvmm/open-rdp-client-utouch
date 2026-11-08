include(GNUInstallDirs)
add_executable(open-rdp-client
    qt/main.cpp qt/DesktopInput.cpp qt/DesktopInput.h
    resources.qrc ${SHARED_DIR}/resources.qrc)
target_include_directories(open-rdp-client PRIVATE qt)
target_link_libraries(open-rdp-client PRIVATE rdp-qt Qt6::QuickControls2 Qt6::Svg)
install(TARGETS open-rdp-client RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES packaging/open-rdp-client.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES ${SHARED_DIR}/assets/logo.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps RENAME open-rdp-client.svg)
install(FILES ${CMAKE_SOURCE_DIR}/LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/doc/open-rdp-client RENAME copyright)
if(BUILD_TESTING)
    find_package(Qt6 6.4 REQUIRED COMPONENTS Test QuickTest)
    add_executable(desktop-input-tests tests/tst_DesktopInput.cpp qt/DesktopInput.cpp qt/DesktopInput.h)
    target_include_directories(desktop-input-tests PRIVATE qt)
    target_link_libraries(desktop-input-tests PRIVATE Qt6::Test Qt6::Quick)
    add_test(NAME desktop-input COMMAND desktop-input-tests)
    add_executable(desktop-qml-tests tests/qml_main.cpp qt/DesktopInput.cpp qt/DesktopInput.h ${SHARED_DIR}/resources.qrc)
    target_include_directories(desktop-qml-tests PRIVATE qt)
    target_link_libraries(desktop-qml-tests PRIVATE rdp-qt Qt6::QuickTest Qt6::QuickControls2)
    add_test(NAME desktop-qml COMMAND desktop-qml-tests -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/qml
        -import ${SHARED_DIR}/qml)
    add_test(NAME shared-qml COMMAND desktop-qml-tests -input ${SHARED_DIR}/tests/qml
        -import ${SHARED_DIR}/qml)
    set_tests_properties(desktop-input desktop-qml shared-qml PROPERTIES
        ENVIRONMENT "QT_QUICK_BACKEND=software;LIBGL_ALWAYS_SOFTWARE=1")
endif()
