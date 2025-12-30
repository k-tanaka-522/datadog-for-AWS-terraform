# 詳細設計 INDEX

## 1. プロジェクト概要

### プロジェクト名
Datadog監視基盤構築（Terraform IaC）

### 目的
既存AWS環境（RDS、ECS、ALB、VPC）に対するDatadog監視設定をTerraformでIaC化し、L0（インフラ）、L2（サービス）、L3（テナント）の3層監視とComposite Monitorによるアラート抑制を実現する。

### スコープ
- AWS基盤構築（VPC、RDS、ECS、ALB）
- Datadog Monitor の作成（L0/L2/L3/Composite）
- Terraform モジュール設計（level0-infra、level2-service、level3-tenant、composite）
- テナント動的管理（for_each）
- State管理（S3 + DynamoDB）

### 基本設計との関連
本詳細設計は、以下の基本設計書を実装レベルに具体化したものです。

| 基本設計書 | 詳細設計での対応 |
|-----------|---------------|
| [01_システム構成図.md](../01_基本設計/01_システム構成図.md) | 全モジュールの構成要素定義 |
| [02_ネットワーク設計.md](../01_基本設計/02_ネットワーク設計.md) | AWS環境パラメータの定義 |
| [03_セキュリティ設計.md](../01_基本設計/03_セキュリティ設計.md) | API Key管理、Secret管理 |
| [05_監視設計.md](../01_基本設計/05_監視設計.md) | Monitor定義の詳細仕様 |
| [10_IaC方針.md](../01_基本設計/10_IaC方針.md) | ディレクトリ構成、モジュール設計 |

---

## 2. ドキュメント構成

本詳細設計は、AWS基盤とDatadog監視設定の2つの領域に分かれています。

### 2.1 全体構成

```
docs/04_インフラ設計/02_詳細設計/
├── INDEX.md              # 全体INDEX（本ドキュメント）
├── aws/                  # AWS基盤（VPC、RDS、ECS、ALB）
│   └── INDEX.md          # AWS詳細設計INDEX
└── datadog/              # Datadog監視設定
    └── INDEX.md          # Datadog詳細設計INDEX
```

### 2.2 AWS基盤詳細設計

AWS基盤（VPC、RDS、ECS、ALB等）のTerraform詳細設計です。

→ 詳細: [aws/INDEX.md](aws/INDEX.md)

### 2.3 Datadog監視詳細設計

Datadog監視設定（L0/L2/L3/Composite Monitor）のTerraform詳細設計です。

→ 詳細: [datadog/INDEX.md](datadog/INDEX.md)

---

## 3. 実装者向けガイド

### 3.1 実装開始時に参照すべきドキュメント

| ドキュメント | パス | 目的 |
|------------|------|------|
| **基本設計書** | | |
| システム構成図 | [../01_基本設計/01_システム構成図.md](../01_基本設計/01_システム構成図.md) | 全体像の理解 |
| 監視設計 | [../01_基本設計/05_監視設計.md](../01_基本設計/05_監視設計.md) | Monitor定義の仕様 |
| IaC方針 | [../01_基本設計/10_IaC方針.md](../01_基本設計/10_IaC方針.md) | ディレクトリ構成、モジュール設計 |
| **詳細設計書** | | |
| このINDEX | [INDEX.md](INDEX.md) | 全体構成 |
| AWS詳細設計 | [aws/INDEX.md](aws/INDEX.md) | AWS基盤の詳細設計 |
| Datadog詳細設計 | [datadog/INDEX.md](datadog/INDEX.md) | Datadog監視の詳細設計 |

---

**作成日**: 2025-12-28（更新: 2025-12-29）
**作成者**: Infra-Architect
**バージョン**: 1.1
**ステータス**: Draft
