pragma Singleton
import QtQuick 2.12

QtObject {
    signal eventJsonReceived(string jsonString)
    signal actionDispatched(var action)
    function dispatchJson(value) { actionDispatched(JSON.parse(value)) }
    function deliverEvent(value) { eventJsonReceived(JSON.stringify(value)) }
}
