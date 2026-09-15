import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: errorState

    property string message: ""
    property string giteaUrl: ""

    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: 8

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "!"
            font.pixelSize: 24
            font.weight: Font.Bold
            color: Quickshell.Colors.error
            opacity: 0.5
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: message || "Something went wrong"
            font.pixelSize: 12
            color: Quickshell.Colors.textSecondary
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.maximumWidth: 300
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: message.indexOf("credentials") !== -1 || message.indexOf("No credentials") !== -1
            text: "Create ~/.config/gitea-workstatus/credentials\nwith GITEA_URL and GITEA_TOKEN"
            font.family: "monospace"
            font.pixelSize: 10
            color: Quickshell.Colors.textMuted
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.4
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: giteaUrl !== ""
            text: "Open Gitea"
            font.pixelSize: 11
            color: Quickshell.Colors.accent
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
