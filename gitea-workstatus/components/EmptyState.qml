import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: empty

    property string section: "attention"

    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: 8

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: {
                switch (section) {
                    case "attention": return "\u2713";
                    case "running": return "\u25CB";
                    case "completed": return "\u2014";
                    default: return "\u2022";
                }
            }
            font.pixelSize: 24
            color: Quickshell.Colors.textMuted
            opacity: 0.3
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: {
                switch (section) {
                    case "attention": return "Nothing needs attention";
                    case "running": return "No jobs running";
                    case "completed": return "No recent completions";
                    case "my_prs": return "No open PRs";
                    case "review": return "No reviews requested";
                    case "all": return "No open pull requests";
                    default: return "Nothing here";
                }
            }
            font.pixelSize: 12
            color: Quickshell.Colors.textMuted
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: section === "attention"
            text: "All clear \u2014 your repos are healthy"
            font.pixelSize: 10
            color: Quickshell.Colors.textMuted
            opacity: 0.5
        }
    }
}
