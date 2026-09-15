import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: empty

    property string section: "attention"

    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: Style.space(8)

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
            font.pixelSize: Style.space(24)
            color: Color.text.muted
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
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
            color: Color.text.muted
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: section === "attention"
            text: "All clear \u2014 your repos are healthy"
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            color: Color.text.muted
            opacity: 0.5
        }
    }
}
