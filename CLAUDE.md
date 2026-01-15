# CLAUDE.md

Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイドラインです。

## 基本ルール

- **日本語で回答してください**

## MCP サーバー

このプロジェクトでは以下の MCP サーバーを使用します。

### apple-docs

SwiftUI や iOS API の最新ドキュメントを参照する際は、apple-docs MCP を使用してください。

```
# 使用例
mcp__apple-docs__search_documentation: SwiftUIのViewに関するドキュメントを検索
mcp__apple-docs__get_documentation: 特定のAPIの詳細ドキュメントを取得
```

### XcodeBuildMCP

コード変更後のビルドには XcodeBuildMCP を使用してください。

```
# 使用例
mcp__XcodeBuildMCP__xcodebuild: プロジェクトをビルド
```

## 開発フロー

コードを変更した際は、以下の順序で実行してください。

1. **SwiftFormat 実行**: コードフォーマットを統一

   ```bash
   swiftformat Packages/
   ```

2. **SwiftLint 実行**: コーディング規約をチェック

   ```bash
   swiftlint lint Packages/
   ```

3. **XcodeBuildMCP でビルド**: ビルドエラーがないか確認
   ```
   mcp__XcodeBuildMCP__build_sim (scheme: PriconneDB, simulatorName: iPhone 17)
   ```
