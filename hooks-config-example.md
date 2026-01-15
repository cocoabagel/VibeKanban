# VibeKanban Claude Code Hooks 設定

VibeKanbanとClaude Codeを連携させるためのHooks設定です。

## 自動設定（推奨）

VibeKanbanでリポジトリを選択すると、自動的にプロジェクトの `.claude/settings.local.json` にHooks設定が追加されます。

**設定ファイルの場所**: `{ワークツリー}/.claude/settings.local.json`

## 手動設定（参考）

手動で設定する場合は、以下の内容を `.claude/settings.local.json` に追加してください。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "[ -n \"$VIBEKANBAN_STATUS_FILE\" ] && echo running > \"$VIBEKANBAN_STATUS_FILE\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "[ -n \"$VIBEKANBAN_STATUS_FILE\" ] && echo idle > \"$VIBEKANBAN_STATUS_FILE\""
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "[ -n \"$VIBEKANBAN_STATUS_FILE\" ] && echo waiting > \"$VIBEKANBAN_STATUS_FILE\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "[ -n \"$VIBEKANBAN_STATUS_FILE\" ] && echo completion > \"$VIBEKANBAN_STATUS_FILE\""
          }
        ]
      }
    ]
  }
}
```

## Hooksの説明

| Hook | タイミング | VibeKanbanステータス |
|------|----------|-------------------|
| PreToolUse | ツール実行前 | RUNNING |
| PostToolUse | ツール実行後 | IDLE |
| PermissionRequest | 権限確認ダイアログ表示時 | WAITING |
| Stop | Claudeエージェント完了時 | COMPLETION |

## 環境変数

- `VIBEKANBAN_STATUS_FILE`: VibeKanbanが設定するステータスファイルのパス
  - 例: `/tmp/vibekanban/{session-id}.status`
  - VibeKanbanがこのファイルを監視してステータスを更新します

## 手動でステータスを変更する場合

ターミナルから直接ステータスを変更することもできます：

```bash
# WAITINGに変更
echo waiting > "$VIBEKANBAN_STATUS_FILE"

# COMPLETIONに変更
echo completion > "$VIBEKANBAN_STATUS_FILE"

# IDLEに変更
echo idle > "$VIBEKANBAN_STATUS_FILE"
```

## 注意事項

- VibeKanbanで新しいセッションを作成すると、ワークツリーにHooks設定が自動的に追加されます
- 既存の `.claude/settings.local.json` がある場合は、既存の設定を保持しつつVibeKanban用の設定をマージします
- `VIBEKANBAN_STATUS_FILE` 環境変数はVibeKanbanから起動したターミナルでのみ設定されます
- 通常のターミナルからClaudeを起動した場合、この設定は影響しません（`-n` チェックでスキップされます）
- 設定変更後は、Claude Codeセッションを再起動してください
