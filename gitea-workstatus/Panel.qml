import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Omarchy.Themes
import Omarchy.Widgets

import "Model.js" as Model
import "components"

PanelSurface {
    id: panel

    property var barWidget: null
    property string activeSection: "attention"
    property string repoFilter: ""
    property int selectedIndex: 0
    property bool isRefreshing: false

    width: Style.space(420)
    height: Math.min(contentCol.implicitHeight + Style.space(24), Style.space(600))

    color: Palette.surface.primary
    border.color: Palette.border.subtle
    border.width: 1
    radius: Style.cornerRadius

    Component.onCompleted: {
        forceActiveFocus();
        updateSection("attention");
    }

    function updateSection(section) {
        activeSection = section;
        Model.setSectionFilter(section);
        selectedIndex = 0;
        listModel.clear();
        populateList();
    }

    function setRepoFilter(repo) {
        repoFilter = repo;
        Model.setRepoFilter(repo);
        selectedIndex = 0;
        listModel.clear();
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

    // Keyboard navigation
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

    ListModel { id: listModel }

    // === Panel Layout ===
    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
                text: "Gitea"
                font.family: Style.font.family
                font.pixelSize: Style.space(16)
                font.weight: Font.DemiBold
                color: Palette.text.primary
            }

            Text {
                text: {
                    var meta = Model.getMeta();
                    return meta ? meta.username : "";
                }
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                color: Palette.text.muted
                visible: text !== ""
            }

            Item { Layout.fillWidth: true }

            // Stale indicator
            Text {
                visible: barWidget && barWidget.stale
                text: "stale"
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Palette.status.warning
                opacity: 0.8
            }

            // Refresh indicator
            Text {
                text: isRefreshing ? "refreshing\u2026" : ""
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Palette.text.muted
                visible: isRefreshing

                SequentialAnimation on opacity {
                    running: isRefreshing
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 500 }
                    NumberAnimation { to: 1.0; duration: 500 }
                }
            }

            // Last updated
            Text {
                text: {
                    var meta = Model.getMeta();
                    return meta ? Model.timeAgo(meta.collected_at) : "";
                }
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Palette.text.muted
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Palette.border.subtle
        }

        // Summary badges row
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)
            visible: !barWidget || !barWidget.hasError

            SummaryBadge {
                label: "Attention"
                count: Model.getBarSummary().attention
                accent: Palette.status.error
                active: activeSection === "attention"
                onClicked: updateSection("attention")
            }
            SummaryBadge {
                label: "Running"
                count: Model.getBarSummary().running
                accent: Palette.status.warning
                active: activeSection === "running"
                onClicked: updateSection("running")
            }
            SummaryBadge {
                label: "Completed"
                count: Model.getRecentlyCompleted().length
                accent: Palette.text.muted
                active: activeSection === "completed"
                onClicked: updateSection("completed")
            }
            SummaryBadge {
                label: "My PRs"
                count: Model.getMyPrs().length
                accent: Palette.accent.primary
                active: activeSection === "my_prs"
                onClicked: updateSection("my_prs")
            }
            SummaryBadge {
                label: "Review"
                count: Model.getReviewQueue().length
                accent: Palette.accent.secondary
                active: activeSection === "review"
                onClicked: updateSection("review")
            }

            Item { Layout.fillWidth: true }
        }

        // Repo filter
        RepoFilter {
            id: repoFilterBar
            Layout.fillWidth: true
            repos: Model.getAllRepos()
            currentFilter: panel.repoFilter
            onFilterChanged: function(repo) { panel.setRepoFilter(repo) }
            visible: Model.getAllRepos().length > 1
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Palette.border.subtle
            visible: listModel.count > 0
        }

        // Error state
        ErrorState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: barWidget && barWidget.hasError
            message: barWidget ? barWidget.errorMsg : "Unknown error"
            giteaUrl: barWidget ? barWidget.giteaUrl : ""
        }

        // Empty state
        EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !barWidget || (!barWidget.hasError && listModel.count === 0)
            section: activeSection
        }

        // Item list
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
                        giteaUrl: barWidget ? (Model.getMeta() ? Model.getMeta().gitea_url : "") : ""
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

        // Footer with keyboard hints
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
                        color: Palette.text.muted
                        opacity: 0.6
                    }
                    Text {
                        text: modelData.action
                        font.family: Style.font.family
                        font.pixelSize: Style.space(9)
                        color: Palette.text.muted
                        opacity: 0.4
                    }
                }
            }
        }
    }

    // Reload when data changes
    Connections {
        target: barWidget
        function onBarSummaryChanged() {
            populateList();
        }
    }
}
