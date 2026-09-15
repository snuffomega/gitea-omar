import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

import "Model.js" as Model
import "components"

PopupCard {
    id: panel

    property var barWidget: null
    property string activeSection: "attention"
    property string repoFilter: ""
    property int selectedIndex: 0
    property bool isRefreshing: false
    // Bind to barWidget.dataRevision so QML re-evaluates when data changes
    property int dataRev: barWidget ? barWidget.dataRevision : 0

    width: 420
    height: Math.min(contentCol.implicitHeight + 24, 600)

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

    // Re-populate when data revision changes
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
            if (barWidget) barWidget.close();
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

    // Compute badge counts reactively via dataRev dependency
    function badgeCount(section) {
        void dataRev; // force re-evaluation
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
        anchors.margins: 12
        spacing: 8

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Gitea"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: Quickshell.Colors.textPrimary
            }

            Text {
                text: {
                    void panel.dataRev;
                    var meta = Model.getMeta();
                    return meta ? meta.username : "";
                }
                font.pixelSize: 12
                color: Quickshell.Colors.textMuted
                visible: text !== ""
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: barWidget && barWidget.stale
                text: "stale"
                font.pixelSize: 10
                color: Quickshell.Colors.warning
                opacity: 0.8
            }

            Text {
                text: isRefreshing ? "refreshing\u2026" : ""
                font.pixelSize: 10
                color: Quickshell.Colors.textMuted
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
                font.pixelSize: 10
                color: Quickshell.Colors.textMuted
            }

            // Partial failure indicator
            Text {
                text: {
                    void panel.dataRev;
                    var meta = Model.getMeta();
                    if (meta && meta.repo_failed > 0) return meta.repo_failed + " repo(s) unreachable";
                    return "";
                }
                font.pixelSize: 10
                color: Quickshell.Colors.warning
                visible: text !== ""
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Quickshell.Colors.border
        }

        // Summary badges — counts are reactive via badgeCount()
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: !barWidget || !barWidget.hasError

            SummaryBadge {
                label: "Attention"
                count: panel.badgeCount("attention")
                accent: Quickshell.Colors.error
                active: activeSection === "attention"
                onClicked: updateSection("attention")
            }
            SummaryBadge {
                label: "Running"
                count: panel.badgeCount("running")
                accent: Quickshell.Colors.warning
                active: activeSection === "running"
                onClicked: updateSection("running")
            }
            SummaryBadge {
                label: "Completed"
                count: panel.badgeCount("completed")
                accent: Quickshell.Colors.textMuted
                active: activeSection === "completed"
                onClicked: updateSection("completed")
            }
            SummaryBadge {
                label: "My PRs"
                count: panel.badgeCount("my_prs")
                accent: Quickshell.Colors.accent
                active: activeSection === "my_prs"
                onClicked: updateSection("my_prs")
            }
            SummaryBadge {
                label: "Review"
                count: panel.badgeCount("review")
                accent: Quickshell.Colors.accentSecondary
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
            color: Quickshell.Colors.border
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
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 4
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
            spacing: 12

            Repeater {
                model: [
                    { key: "j/k", action: "navigate" },
                    { key: "h/l", action: "sections" },
                    { key: "\u21B5", action: "open" },
                    { key: "r", action: "refresh" }
                ]
                Row {
                    spacing: 3
                    Text {
                        text: modelData.key
                        font.family: "monospace"
                        font.pixelSize: 9
                        color: Quickshell.Colors.textMuted
                        opacity: 0.6
                    }
                    Text {
                        text: modelData.action
                        font.pixelSize: 9
                        color: Quickshell.Colors.textMuted
                        opacity: 0.4
                    }
                }
            }
        }
    }
}
