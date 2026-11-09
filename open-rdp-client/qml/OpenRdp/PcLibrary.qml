import QtQuick 2.12

QtObject {
    property var profiles: []
    property string query: ""
    property string view: "all"
    property string group: ""
    property string sort: "name"
    readonly property var groupNames: {
        var names = [];
        for (var i = 0; i < profiles.length; ++i) {
            var name = profiles[i].groupName || "Saved PCs";
            if (names.indexOf(name) < 0)
                names.push(name);
        }
        return names.sort(function (a, b) {
                return a.localeCompare(b);
            });
    }
    readonly property var visibleProfiles: {
        var needle = query.trim().toLowerCase();
        var result = profiles.filter(function (pc) {
                return (view !== "favorites" || pc.favorite) && (view !== "recent" || pc.lastConnectedEpoch > 0) && (!group || (pc.groupName || "Saved PCs") === group) && (!needle || ((pc.displayTitle || "") + " " + (pc.address || "") + " " + (pc.groupName || "")).toLowerCase().indexOf(needle) >= 0);
            });
        var order = view === "recent" ? "recent" : sort;
        return result.sort(function (a, b) {
                if (order === "recent") {
                    var recent = (b.lastConnectedEpoch || 0) - (a.lastConnectedEpoch || 0);
                    if (recent)
                        return recent;
                }
                var left = order === "address" ? a.address : a.displayTitle;
                var right = order === "address" ? b.address : b.displayTitle;
                return (left || "").localeCompare(right || "", undefined, {
                        "sensitivity": "base"
                    }) || (a.id || "").localeCompare(b.id || "");
            });
    }
    function thumbnailUrl(path) {
        if (!path)
            return "";
        if (path.indexOf("file://") === 0 || path.indexOf("qrc:/") === 0)
            return path;
        return path.charAt(0) === "/" ? "file://" + path : "";
    }
}
