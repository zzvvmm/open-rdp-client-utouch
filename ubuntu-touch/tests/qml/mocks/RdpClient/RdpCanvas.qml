import QtQuick 2.12

// Layout/input tests use the real viewport with a non-rendering canvas stub.
Item {
    property var controller
    function requestRepaint() {}
}
