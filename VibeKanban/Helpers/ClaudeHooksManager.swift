import Foundation

// MARK: - Claude Hooks Manager

enum ClaudeHooksManager {
    /// VibeKanban用のHooks設定
    private static func getVibeKanbanHooks() -> [String: Any] {
        [
            "PreToolUse": [
                [
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "[ -n \"$VIBEKANBAN_STATUS_FILE\" ] && echo running > \"$VIBEKANBAN_STATUS_FILE\""
                        ]
                    ]
                ]
            ],
            "Notification": [
                [
                    "matcher": "permission_prompt",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "[ -n \"$VIBEKANBAN_STATUS_FILE\" ] && echo waiting > \"$VIBEKANBAN_STATUS_FILE\""
                        ]
                    ]
                ]
            ],
            "Stop": [
                [
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "[ -n \"$VIBEKANBAN_STATUS_FILE\" ] && echo completion > \"$VIBEKANBAN_STATUS_FILE\""
                        ]
                    ]
                ]
            ]
        ]
    }

    /// プロジェクトの.claude/settings.local.jsonにHooks設定を追加
    static func setupHooksForProject(at projectPath: String) {
        let projectURL = URL(fileURLWithPath: projectPath)
        let claudeDir = projectURL.appendingPathComponent(".claude").path
        let settingsPath = projectURL.appendingPathComponent(".claude/settings.local.json").path

        let fileManager = FileManager.default

        // .claudeディレクトリを作成
        if !fileManager.fileExists(atPath: claudeDir) {
            do {
                try fileManager.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
            } catch {
                return
            }
        }

        // 既存の設定を読み込むか、新規作成
        var settings: [String: Any] = [:]

        if fileManager.fileExists(atPath: settingsPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
                if let existingSettings = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings = existingSettings
                }
            } catch {
                // Continue with empty settings
            }
        }

        // Hooks設定をマージ
        settings = mergeHooksIntoSettings(settings)

        // 設定を書き込み
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: settingsPath))
        } catch {}
    }

    /// 既存の設定にHooksをマージ
    private static func mergeHooksIntoSettings(_ settings: [String: Any]) -> [String: Any] {
        var result = settings

        // 既存のhooksを取得または新規作成
        var existingHooks = (settings["hooks"] as? [String: Any]) ?? [:]

        // 各hookタイプをマージ
        for (hookType, hookConfigs) in getVibeKanbanHooks() {
            guard let newConfigs = hookConfigs as? [[String: Any]] else { continue }

            var existingConfigs = (existingHooks[hookType] as? [[String: Any]]) ?? []

            // VibeKanban用の設定を追加（既存のVibeKanban設定は置き換え）
            for newConfig in newConfigs {
                // 既存のVibeKanban設定を削除
                existingConfigs.removeAll { config in
                    if let hooks = config["hooks"] as? [String] {
                        return hooks.contains { $0.contains("VIBEKANBAN_STATUS_FILE") }
                    }
                    return false
                }
                // 新しい設定を追加
                existingConfigs.append(newConfig)
            }

            existingHooks[hookType] = existingConfigs
        }

        result["hooks"] = existingHooks
        return result
    }
}
