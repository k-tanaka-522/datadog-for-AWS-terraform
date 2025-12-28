# インフラ基本設計書 INDEX

## プロジェクト概要

| 項目 | 内容 |
|------|------|
| プロジェクト名 | Datadog for AWS Terraform PoC |
| 目的 | Datadog Composite Monitor による階層監視の実現、IaCによるテナント追加効率化 |
| スコープ | L0/L2/L3 階層監視、Terraform モジュール化、テナント追加自動化 |
| 環境 | PoC環境（AWS既存環境 + Datadog） |

## ドキュメント構成

### インフラ設計（infra-architect担当）

| ドキュメント | 概要 | レビュー状況 |
|------------|------|-------------|
| [01_システム構成図.md](01_システム構成図.md) | 全体構成図、監視対象リソース | 🔄 作成中 |
| [02_ネットワーク設計.md](02_ネットワーク設計.md) | VPC構成（PoC環境） | 🔄 作成中 |
| [03_セキュリティ設計.md](03_セキュリティ設計.md) | Datadog API Key管理、IAM権限 | 🔄 作成中 |
| [05_監視設計.md](05_監視設計.md) | **Composite Monitor階層設計（最重要）** | 🔄 作成中 |
| [06_バックアップ設計.md](06_バックアップ設計.md) | Terraform State バックアップ戦略 | 🔄 作成中 |
| [10_IaC方針.md](10_IaC方針.md) | Terraformディレクトリ構成、モジュール分割 | 🔄 作成中 |

## 重要な設計判断（ADR サマリー）

| ADR | 決定事項 | 理由 |
|-----|---------|------|
| ADR-001 | IaCツールにTerraformを採用 | Datadog Providerの豊富さ、マルチクラウド対応 |
| ADR-002 | Composite Monitorで3階層監視（L0/L2/L3） | アラートストーム防止、原因特定の迅速化 |
| ADR-003 | テナント管理を for_each で実装 | テナント追加時の差分最小化、再現性確保 |
| ADR-004 | State管理を S3 + DynamoDB で実施 | ロック機能、バージョン管理、チーム開発対応 |

## 特記事項

### PoCの特徴
- **主目的**: Datadog Composite Monitor の有効性検証
- **監視対象**: 既存AWS環境（RDS、ECS、ALB、VPC）
- **新規構築**: Datadog監視設定のみ（AWSリソースは既存利用）
- **テナント構成**: tenant-a（初期）、tenant-b（追加検証）、tenant-c（再現性確認）

### 設計の重点
1. **05_監視設計.md**: Composite Monitor の親子関係、アラート抑制ロジック
2. **10_IaC方針.md**: Terraform モジュール構成（4モジュール）、テナント追加手順

## レビュー・承認

- レビュー担当者: SRE（実装可能性）、Consultant（ビジネス要件整合）
- 承認者: PM
- 承認日: 未定

## 関連ドキュメント

| ドキュメント | パス |
|-------------|------|
| 要件定義書 | docs/02_要件定義/要件定義書.md |
| 事業計画書 | docs/01_企画/事業計画書.md |
| アーキテクチャ設計パターン | docs/01_企画/architecture.md |
| 監視設計（企画） | docs/01_企画/monitoring-design.md |
| Terraform技術標準 | .claude/docs/40_standards/42_infra/iac/terraform.md |
| セキュリティ基準 | .claude/docs/40_standards/49_common/security.md |

---

**作成日**: 2025-12-28
**作成者**: Infra-Architect
**バージョン**: 1.0
**ステータス**: Draft
