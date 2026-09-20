import Foundation

/// 会话级 UI 进度/加载态 — 与订阅数据（feeds）分域观察，避免刷新进度牵动整库列表 diff
@Observable
@MainActor
final class SessionChromeState {
    var isLoading = false
    var isRefreshingAll = false
    var refreshProgressCurrent = 0
    var refreshProgressTotal = 0
    var refreshProgressTitle = ""
    var listTranslationProgressText = ""
    private(set) var listTranslationSessionID = 0

    func cancelListTranslation() {
        listTranslationSessionID += 1
        listTranslationProgressText = ""
    }

    @discardableResult
    func beginListTranslationSession() -> Int {
        listTranslationSessionID += 1
        return listTranslationSessionID
    }

    func isListTranslationSessionValid(_ session: Int) -> Bool {
        session == listTranslationSessionID
    }

    func beginRefreshAll(feedCount: Int) {
        isRefreshingAll = true
        isLoading = true
        refreshProgressTotal = feedCount
        refreshProgressCurrent = 0
        refreshProgressTitle = "准备中…"
    }

    func endRefreshChrome(cancelled: Bool, completed: Int, total: Int) {
        refreshProgressCurrent = cancelled ? completed : total
        refreshProgressTitle = cancelled ? "已取消" : "完成"
    }

    func clearRefreshChrome() {
        isRefreshingAll = false
        isLoading = false
        refreshProgressCurrent = 0
        refreshProgressTotal = 0
        refreshProgressTitle = ""
    }
}
