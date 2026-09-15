// Model.js — State management for Gitea Work Status plugin
.pragma library

var _data = null;
var _error = null;
var _loading = false;
var _lastNotified = {};
var _mutedRepos = {};
var _repoFilter = "";
var _sectionFilter = "attention"; // attention | running | completed | my_prs | review | all

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

// Bar summary: compact counts for the bar widget
function getBarSummary() {
    var s = getSummary();
    if (!s) return { total: 0, attention: 0, running: 0, failed: 0, review: 0, healthy: true };
    return {
        total: s.open_prs || 0,
        attention: s.needs_attention || 0,
        running: s.running_jobs || 0,
        failed: s.ci_failed || 0,
        review: s.review_requested || 0,
        ready: s.ready_to_merge || 0,
        healthy: (s.needs_attention || 0) === 0 && (s.ci_failed || 0) === 0
    };
}

// Notification deduplication
function shouldNotify(key) {
    var now = Date.now();
    var last = _lastNotified[key];
    if (last && (now - last) < 600000) return false; // 10 min dedup
    _lastNotified[key] = now;
    return true;
}

function getNewNotifications(prevSummary) {
    var curr = getSummary();
    if (!curr || !prevSummary) return [];
    var notes = [];

    if ((curr.ci_failed || 0) > (prevSummary.ci_failed || 0)) {
        var key = "ci_fail_" + curr.ci_failed;
        if (shouldNotify(key))
            notes.push({ type: "failure", message: "CI failure detected", count: curr.ci_failed });
    }
    if ((curr.review_requested || 0) > (prevSummary.review_requested || 0)) {
        var rkey = "review_" + curr.review_requested;
        if (shouldNotify(rkey))
            notes.push({ type: "review", message: "New review requested", count: curr.review_requested });
    }
    return notes;
}

// Relative time formatting
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
        case "ci_failed": return "\u2718";    // X
        case "changes_requested": return "\u21BA"; // ↺
        case "review_requested": return "\u25CF";  // ●
        case "ci_running": return "\u25E6";   // ◦
        case "ready": return "\u2714";        // ✔
        case "approved": return "\u2713";     // ✓
        case "ci_passed": return "\u25CB";    // ○
        default: return "\u2022";             // •
    }
}
