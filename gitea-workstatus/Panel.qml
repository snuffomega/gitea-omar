import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui as Ui

import "Model.js" as Model
import "components"

Ui.PopupCard {
    id: panel

    required property Item anchorItem
    required property QtObject bar

    property var barWidget: null
    property string activeSection: "attention"
    property string repoFilter: ""
    property int selectedIndex: 0
    property bool isRefreshing: false
    property int dataRev: barWidget ? barWidget.dataRevision : 0

    contentWidth: Style.space(420)
    contentHeight: Math.min(contentCol.implicitHeight + Style.space(24), Style.space(600))

    Component.onCompleted: {
        forceActiveFocus();
        updateSection("attention");
    }

    function updateSection(section) {
        activeSection = section;
        Model.setSectionFilter(section);
        selectedIndex = 0;
        populateList();
    }

    function setRepoFilter(repo) {
        repoFilter = repo;
        Model.setRepoFilter(repo);
        selectedIndex = 0;
        populateList();
    }

    function populateList() {
        listModel.clear();
        var items;
        if (activeSection === "running" || activeSection === "completed") {
            items = activeSection === "running" ? Model.getRunningJobs() : Model.getRecentlyCompleted();
            for (var j = 0; j < items.length; j++) {
                listModel.append({ itemData: JSON.stringify(items[j]), itemType: "job" });
            }
        } else {
            items = Model.getActiveSection();
            for (var i = 0; i < items.length; i++) {
                listModel.append({ itemData: JSON.stringify(items[i]), itemType: "pr" });
            }
        }
    }

    function openSelected() {
        if (selectedIndex < 0 || selectedIndex >= listModel.count) return;
        var item = JSON.parse(listModel.get(selectedIndex).itemData);
        if (item.url) Qt.openUrlExternally(item.url);
    }

    function openRepo(repo) {
        var meta = Model.getMeta();
        if (meta && meta.gitea_url && repo) {
            Qt.openUrlExternally(meta.gitea_url + "/" + repo);
        }
    }

    onDataRevChanged: populateList()

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_J:
        case Qt.Key_Down:
            selectedIndex = Math.min(selectedIndex + 1, listModel.count - 1);
            event.accepted = true; break;
        case Qt.Key_K:
        case Qt.Key_Up:
            selectedIndex = Math.max(selectedIndex - 1, 0);
            event.accepted = true; break;
        case Qt.Key_G:
            if (event.modifiers & Qt.ShiftModifier) selectedIndex = listModel.count - 1;
            else selectedIndex = 0;
            event.accepted = true; break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            openSelected();
            event.accepted = true; break;
        case Qt.Key_H:
        case Qt.Key_Left:
            cycleSectionPrev();
            event.accepted = true; break;
        case Qt.Key_L:
        case Qt.Key_Right:
            cycleSectionNext();
            event.accepted = true; break;
        case Qt.Key_R:
            if (barWidget) barWidget.refresh();
            isRefreshing = true;
            refreshTimer.restart();
            event.accepted = true; break;
        case Qt.Key_Escape:
            panel.close();
            event.accepted = true; break;
        case Qt.Key_Tab:
            event.accepted = true; break;
        }
    }

    Timer {
        id: refreshTimer
        interval: 2000
        onTriggered: isRefreshing = false
    }

    property var sectionOrder: ["attention", "running", "completed", "my_prs", "review", "all"]

    function cycleSectionNext() {
        var idx = sectionOrder.indexOf(activeSection);
        updateSection(sectionOrder[(idx + 1) % sectionOrder.length]);
    }
    function cycleSectionPrev() {
        var idx = sectionOrder.indexOf(activeSection);
        updateSection(sectionOrder[(idx - 1 + sectionOrder.length) % sectionOrder.length]);
    }

    function badgeCount(section) {
        void dataRev;
        switch (section) {
            case "attention": return Model.getAttentionItems().length;
            case "running": return Model.getRunningJobs().length;
            case "completed": return Model.getRecentlyCompleted().length;
            case "my_prs": return Model.getMyPrs().length;
            case "review": return Model.getReviewQueue().length;
            default: return 0;
        }
    }

    ListModel { id: listModel }

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        spacing: Style.space(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
                text: "Gitea"
                font.family: Style.font.family
                font.pixelSize: Style.space(16)
                font.weight: Font.DemiBold
                color: Color.text.primary
            }

            Text {
                text: {
                    void panel.dataRev;
                    var meta = Model.getMeta();
                    return meta ? meta.username : "";
                }
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                color: Color.text.muted
                visible: text !== ""
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: barWidget && barWidget.stale
                text: "stale"
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Color.status.warning
                opacity: 0.8
            }

            Text {
                text: isRefreshing ? "refreshing\u2026" : ""
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Color.text.muted
                visible: isRefreshing

                SequentialAnimation on opacity {
                    running: isRefreshing
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 500 }
                    NumberAnimation { to: 1.0; duration: 500 }
                }
            }

            Text {
                text: {
                    void panel.dataRev;
                    var meta = Model.getMeta();
                    return meta ? Model.timeAgo(meta.collected_at) : "";
                }
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Color.text.muted
            }

            Text {
                text: {
                    void panel.dataRev;
                    var meta = Model.getMeta();
                    if (meta && meta.repo_failed > 0) return meta.repo_failed + " repo(s) unreachable";
                    return "";
                }
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Color.status.warning
                visible: text !== ""
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Color.popups.border
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)
            visible: !barWidget || !barWidget.hasError

            SummaryBadge {
                label: "Attention"
                count: panel.badgeCount("attention")
                accent: Color.status.error
                active: activeSection === "attention"
                onClicked: updateSection("attention")
            }
            SummaryBadge {
                label: "Running"
                count: panel.badgeCount("running")
                accent: Color.status.warning
                active: activeSection === "running"
                onClicked: updateSection("running")
            }
            SummaryBadge {
                label: "Completed"
                count: panel.badgeCount("completed")
                accent: Color.text.muted
                active: activeSection === "completed"
                onClicked: updateSection("completed")
            }
            SummaryBadge {
                label: "My PRs"
                count: panel.badgeCount("my_prs")
                accent: Color.accent.primary
                active: activeSection === "my_prs"
                onClicked: updateSection("my_prs")
            }
            SummaryBadge {
                label: "Review"
                count: panel.badgeCount("review")
                accent: Color.accent.secondary
                active: activeSection === "review"
                onClicked: updateSection("review")
            }

            Item { Layout.fillWidth: true }
        }

        RepoFilter {
            id: repoFilterBar
            Layout.fillWidth: true
            repos: { void panel.dataRev; return Model.getAllRepos(); }
            currentFilter: panel.repoFilter
            onFilterChanged: function(repo) { panel.setRepoFilter(repo) }
            visible: { void panel.dataRev; return Model.getAllRepos().length > 1; }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Color.popups.border
            visible: listModel.count > 0
        }

        ErrorState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: barWidget && barWidget.hasError
            message: barWidget ? barWidget.errorMsg : "Unknown error"
            giteaUrl: barWidget ? barWidget.giteaUrl : ""
        }

        EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !barWidget || (!barWidget.hasError && listModel.count === 0)
            section: activeSection
        }

        ListView {
            id: itemList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: listModel.count > 0 && !(barWidget && barWidget.hasError)
            model: listModel
            currentIndex: panel.selectedIndex
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: Style.space(4)
            }

            delegate: Loader {
                width: itemList.width
                property var parsedData: JSON.parse(itemData)
                property bool isSelected: index === panel.selectedIndex

                sourceComponent: itemType === "pr" ? prRowComponent : jobRowComponent

                Component {
                    id: prRowComponent
                    PrRow {
                        data: parsedData
                        selected: isSelected
                        giteaUrl: {
                            void panel.dataRev;
                            var meta = Model.getMeta();
                            return meta ? meta.gitea_url : "";
                        }
                        onOpenPr: Qt.openUrlExternally(data.url)
                        onOpenRepo: panel.openRepo(data.repo)
                    }
                }

                Component {
                    id: jobRowComponent
                    JobRow {
                        data: parsedData
                        selected: isSelected
                        onOpenJob: Qt.openUrlExternally(data.url)
                        onOpenRepo: panel.openRepo(data.repo)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Repeater {
                model: [
                    { key: "j/k", action: "navigate" },
                    { key: "h/l", action: "sections" },
                    { key: "\u21B5", action: "open" },
                    { key: "r", action: "refresh" }
                ]
                Row {
                    spacing: Style.space(3)
                    Text {
                        text: modelData.key
                        font.family: Style.font.monospace
                        font.pixelSize: Style.space(9)
                        color: Color.text.muted
                        opacity: 0.6
                    }
                    Text {
                        text: modelData.action
                        font.family: Style.font.family
                        font.pixelSize: Style.space(9)
                        color: Color.text.muted
                        opacity: 0.4
                    }
                }
            }
        }
    }
}
