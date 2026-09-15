// Model.js — State management for Gitea Work Status plugin
.pragma library

var _data = null;
var _error = null;
var _loading = false;
var _mutedRepos = {};
var _repoFilter = "";
var _sectionFilter = "attention";

// Notification state: keyed by "type:repo:id" → { status, notifiedAt }
var _notifyState = {};

// Revision counter: incremented on every data change so QML can bind to it
var _revision = 0;

function revision() { return _revision; }

function setMutedRepos(csv) {
    _mutedRepos = {};
    if (!csv) return;
    csv.split(",").forEach(function(r) {
        var trimmed = r.trim();
        if (trimmed) _mutedRepos[trimmed] = true;
    });
}

function isMuted(repo) {
    return !!_mutedRepos[repo];
}

function setRepoFilter(repo) {
    _repoFilter = repo || "";
}

function setSectionFilter(section) {
    _sectionFilter = section || "attention";
}

function parseOverview(jsonText) {
    try {
        _data = JSON.parse(jsonText);
        _error = null;
        _revision++;
        return true;
    } catch (e) {
        _error = "Failed to parse status data";
        return false;
    }
}

function getData() { return _data; }
function getError() { return _error; }
function isLoading() { return _loading; }
function setLoading(v) { _loading = v; }

function getSummary() {
    if (!_data) return null;
    return _data.summary || {};
}

function getMeta() {
    if (!_data) return null;
    return _data.meta || {};
}

function getRepos() {
    if (!_data) return [];
    return (_data.repos || []).filter(function(r) { return !isMuted(r); });
}

function getAllRepos() {
    if (!_data) return [];
    return _data.repos || [];
}

function filterByRepo(items) {
    if (!_repoFilter) return items;
    return items.filter(function(item) {
        return item.repo === _repoFilter;
    });
}

function filterMuted(items) {
    return items.filter(function(item) {
        return !isMuted(item.repo);
    });
}

function applyFilters(items) {
    return filterByRepo(filterMuted(items));
}

function getAttentionItems() {
    if (!_data || !_data.sections) return [];
    return applyFilters(_data.sections.attention || []);
}

function getRunningJobs() {
    if (!_data || !_data.sections) return [];
    return applyFilters(_data.sections.running || []);
}

function getRecentlyCompleted() {
    if (!_data || !_data.sections) return [];
    return applyFilters(_data.sections.recently_completed || []);
}

function getMyPrs() {
    if (!_data || !_data.sections) return [];
    return applyFilters(_data.sections.my_prs || []);
}

function getReviewQueue() {
    if (!_data || !_data.sections) return [];
    return applyFilters(_data.sections.review_queue || []);
}

function getAllPrs() {
    if (!_data || !_data.sections) return [];
    return applyFilters(_data.sections.all_prs || []);
}

function getActiveSection() {
    switch (_sectionFilter) {
        case "attention": return getAttentionItems();
        case "running": return getRunningJobs();
        case "completed": return getRecentlyCompleted();
        case "my_prs": return getMyPrs();
        case "review": return getReviewQueue();
        case "all": return getAllPrs();
        default: return getAttentionItems();
    }
}

function getActiveSectionName() { return _sectionFilter; }

// Bar summary: uses filtered (muted-aware) data
function getBarSummary() {
    if (!_data || !_data.sections) return { total: 0, attention: 0, running: 0, failed: 0, review: 0, ready: 0, healthy: true };
    var allPrs = filterMuted(_data.sections.all_prs || []);
    var attentionPrs = filterMuted(_data.sections.attention || []);
    var runningJobs = filterMuted(_data.sections.running || []);

    var failed = 0, review = 0, ready = 0;
    for (var i = 0; i < allPrs.length; i++) {
        var p = allPrs[i];
        if (p.status_label === "ci_failed") failed++;
        if (p.status_label === "review_requested") review++;
        if (p.status_label === "ready") ready++;
    }

    return {
        total: allPrs.length,
        attention: attentionPrs.length,
        running: runningJobs.length,
        failed: failed,
        review: review,
        ready: ready,
        healthy: attentionPrs.length === 0 && failed === 0
    };
}

// Identity-based notification detection.
// Tracks each PR/run by "type:repo:id" and fires only on status transitions.
// A PR that stays failed across refreshes does NOT re-alert.
// A different PR failing (even if total count stays the same) DOES alert.
function getNewNotifications(notifyFailure, notifyReview) {
    var notes = [];
    if (!_data || !_data.sections) return notes;
    var now = Date.now();
    var seen = {};

    if (notifyFailure) {
        var allPrs = filterMuted(_data.sections.all_prs || []);
        for (var i = 0; i < allPrs.length; i++) {
            var pr = allPrs[i];
            var key = "ci:" + pr.repo + ":" + pr.id;
            seen[key] = pr.status_label;

            if (pr.status_label === "ci_failed") {
                var prev = _notifyState[key];
                if (!prev || prev.status !== "ci_failed") {
                    notes.push({
                        type: "failure",
                        message: "CI failed on " + pr.repo + " #" + pr.id + ": " + pr.title
                    });
                }
            }
        }

        var runs = filterMuted(_data.sections.recently_completed || []);
        for (var j = 0; j < runs.length; j++) {
            var run = runs[j];
            var rkey = "run:" + run.repo + ":" + run.id;
            seen[rkey] = run.status;

            if (run.status === "failure") {
                var rprev = _notifyState[rkey];
                if (!rprev || rprev.status !== "failure") {
                    notes.push({
                        type: "failure",
                        message: "Job failed: " + run.workflow + " on " + run.repo
                    });
                }
            }
        }
    }

    if (notifyReview) {
        var reviewQueue = filterMuted(_data.sections.review_queue || []);
        for (var k = 0; k < reviewQueue.length; k++) {
            var rpr = reviewQueue[k];
            var rvkey = "review:" + rpr.repo + ":" + rpr.id;
            seen[rvkey] = "review_requested";

            var rvprev = _notifyState[rvkey];
            if (!rvprev || rvprev.status !== "review_requested") {
                notes.push({
                    type: "review",
                    message: "Review requested: " + rpr.repo + " #" + rpr.id + ": " + rpr.title
                });
            }
        }
    }

    // Update state: record current status, clear items no longer present
    var newState = {};
    for (var skey in seen) {
        newState[skey] = { status: seen[skey], notifiedAt: now };
    }
    _notifyState = newState;

    return notes;
}

function timeAgo(isoString) {
    if (!isoString) return "";
    var then = new Date(isoString).getTime();
    var now = Date.now();
    var diff = Math.floor((now - then) / 1000);
    if (diff < 60) return "just now";
    if (diff < 3600) return Math.floor(diff / 60) + "m ago";
    if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
    if (diff < 604800) return Math.floor(diff / 86400) + "d ago";
    return new Date(isoString).toLocaleDateString();
}

function statusIcon(label) {
    switch (label) {
        case "ci_failed": return "\u2718";
        case "changes_requested": return "\u21BA";
        case "review_requested": return "\u25CF";
        case "ci_running": return "\u25E6";
        case "ready": return "\u2714";
        case "approved": return "\u2713";
        case "approved_ci_passed": return "\u2713";
        case "ci_passed": return "\u25CB";
        case "draft": return "\u25CC";
        case "conflicted": return "\u26A0";
        default: return "\u2022";
    }
}
