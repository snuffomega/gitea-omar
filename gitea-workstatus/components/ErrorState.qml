import QtQuick
import QtQuick.Layouts
import Omarchy.Themes

Item {
    id: errorState

    property string message: ""
    property string giteaUrl: ""

    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "!"
            font.pixelSize: Style.space(24)
            font.weight: Font.Bold
            color: Palette.status.error
            opacity: 0.5
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: message || "Something went wrong"
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
            color: Palette.text.secondary
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Style.space(300)
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: message.indexOf("credentials") !== -1 || message.indexOf("No credentials") !== -1
            text: "Create ~/.config/gitea-workstatus/credentials\nwith GITEA_URL and GITEA_TOKEN"
            font.family: Style.font.monospace
            font.pixelSize: Style.space(10)
            color: Palette.text.muted
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.4
        }

        // Open Gitea link
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: giteaUrl !== ""
            text: "Open Gitea"
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
            color: Palette.accent.primary
            opacity: linkMouse.containsMouse ? 1.0 : 0.7

            MouseArea {
                id: linkMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(giteaUrl)
            }
        }
    }
}
