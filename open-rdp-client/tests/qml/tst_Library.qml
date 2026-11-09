import QtQuick 2.12
import QtTest 1.2
import OpenRdp 1.0

Item {
    width: 700
    height: 500
    PcLibrary {
        id: library
    }
    ActionButton {
        id: button
        text: "Connect"
        x: 10
        y: 10
    }
    SignalSpy {
        id: clicks
        target: button
        signalName: "clicked"
    }
    TestCase {
        name: "PcLibrary"
        when: windowShown
        function init() {
            library.profiles = [{
                    "id": "b",
                    "displayTitle": "Beta",
                    "address": "10.0.0.2",
                    "groupName": "Office",
                    "favorite": false,
                    "lastConnectedEpoch": 20
                }, {
                    "id": "a",
                    "displayTitle": "Alpha",
                    "address": "10.0.0.3",
                    "groupName": "Home",
                    "favorite": true,
                    "lastConnectedEpoch": 0
                }, {
                    "id": "c",
                    "displayTitle": "Charlie",
                    "address": "10.0.0.1",
                    "groupName": "Office",
                    "favorite": true,
                    "lastConnectedEpoch": 40
                }];
            library.query = "";
            library.view = "all";
            library.group = "";
            library.sort = "name";
            clicks.clear();
        }
        function cleanup() { Design.fontScale = 1.0 }
        function ids() {
            return library.visibleProfiles.map(function (pc) {
                    return pc.id;
                }).join(",");
        }
        function test_sorting_does_not_mutate_profiles() {
            compare(ids(), "a,b,c");
            library.sort = "address";
            compare(ids(), "c,b,a");
            library.sort = "recent";
            compare(ids(), "c,b,a");
            compare(library.profiles[0].id, "b");
        }
        function test_combines_groups_favorites_recents_and_trimmed_search() {
            library.view = "favorites";
            compare(ids(), "a,c");
            library.group = "Office";
            compare(ids(), "c");
            library.query = "  10.0.0.1  ";
            compare(ids(), "c");
            library.query = "no match";
            compare(ids(), "");
            library.query = "";
            library.group = "";
            library.view = "recent";
            compare(ids(), "c,b");
            compare(library.groupNames.join(","), "Home,Office");
        }
        function test_thumbnail_paths_have_one_scheme_and_no_remote_fetch() {
            compare(library.thumbnailUrl("file:///tmp/snapshot.png"), "file:///tmp/snapshot.png");
            compare(library.thumbnailUrl("/tmp/snapshot.png"), "file:///tmp/snapshot.png");
            compare(library.thumbnailUrl("https://example.test/private.png"), "");
            compare(library.thumbnailUrl(""), "");
        }
        function test_larger_shared_fonts_expand_button_geometry() {
            var width = button.implicitWidth
            var size = Design.textSize
            Design.fontScale = 1.5
            verify(Design.textSize > size)
            verify(button.implicitWidth > width)
            verify(button.implicitHeight >= 48)
            Design.fontScale = 1.0
        }
        function test_action_button_is_keyboard_accessible_and_balanced() {
            button.forceActiveFocus();
            keyClick(Qt.Key_Space);
            compare(clicks.count, 1);
            keyClick(Qt.Key_Return);
            compare(clicks.count, 2);
            button.enabled = false;
            mouseClick(button);
            compare(clicks.count, 2);
            button.enabled = true;
        }
    }
}
