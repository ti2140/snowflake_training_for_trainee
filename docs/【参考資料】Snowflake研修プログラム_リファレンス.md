# Snowflake 研修プログラム リファレンス

最終更新：2026/6/1

---

## 目次

1. [本番プロダクト（Anchor）概要](#1-本番プロダクトanchor概要)
2. [Git](#2-git)
3. [GitHub](#3-github)
4. [Git 運用ルール](#4-git-運用ルール)
5. [Terraform](#5-terraform)
6. [dbt](#6-dbt)
7. [CI/CD パイプライン](#7-cicd-パイプライン)
8. [AWS 環境構築](#8-aws-環境構築)
9. [Snowflake 環境構築](#9-snowflake-環境構築)

---

## 1. 本番プロダクト（Anchor）概要

### 1.1 研修環境と本番環境の違い

本番 Anchor は Microsoft Graph API との連携・AWS ECS による Docker 環境を採用し、完全自動化されたパイプラインを実現している。研修環境では以下の通り置き換えを行っている。

| 本番 | 研修環境 |
| --- | --- |
| Microsoft Graph API によるメール自動取得 | S3 への手動アップロード |
| AWS ECS（常時稼働） | AWS Lambda（イベント駆動） |

研修環境はユーザーが明示的に操作した場合にのみ動作する。構造上の複雑さは本番と同等であるため、各実装が「何を目的として存在するか」を意識しながら進めること。

### 1.2 メール取得から表示までのフロー

メールが到着してから可視化されるまでは「取得・蓄積」「正規化」「フロントエンド表示」の 3 フェーズに分かれる。

#### Step 1：取得と蓄積（Ingest）

- **認証と接続**：ECS 上のパイプラインが Microsoft Graph API を使用して Outlook へ接続する。運用環境では `client_credentials` モードによる手動認証なしの自動取得を行う。
- **差分取得**：Graph delta query を利用し、前回実行時以降の未取得メールのみを抽出する。この状態（deltaLink）は S3 等のストレージに永続保存される。
- **Snowflake への格納**：取得したメール本文はテキスト化され、`message_id` をキーとして `MAILS_RAW` テーブルへ upsert（重複排除して保存）される。

#### Step 2：正規化（Cortex による処理）

- **カテゴリ判定**：Snowflake に格納された raw データに対し、Snowflake Cortex やルールベースの処理を用いて「案件 (job)」「人材 (candidate)」「その他 (other)」に分類する。
- **情報抽出**：分類に基づき、勤務地・単価・必須スキル・年齢等の項目を抽出する。
- **構造化**：抽出結果を `normalized_result` という JSON 形式のスキーマに整形し、元のメールレコードに付与する。

#### Step 3：アプリケーション表示

- Streamlit が Snowflake に接続し、正規化済みのデータを読み込む。
- ユーザーは構造化された情報をもとに、メール一覧の閲覧・検索・詳細確認を行う。

### 1.3 未実装事項（仕様書未記載）

以下の点は現行ドキュメントに具体的な記載がない。

- **Streamlit の実装詳細**：UI レイアウトおよび表示ロジックの仕様書が存在しない。
- **正規化処理の起動トリガー**：Snowflake Cortex による正規化をいつ実行するか（Stream 処理か定期 Task か）の詳細設計が未定。
- **エラー通知体制**：ECS 定期実行において認証エラーや Snowflake 書き込み失敗が発生した際の通知手段（Slack・メール等）が未定義。
- **削除済みメールの同期**：Delta query で削除イベント（`@removed`）を検知した際に、Snowflake 格納済みレコードをどう扱うか（論理削除・維持等）の運用方針が未記載。

---

## 2. Git

### 2.1 Git とは

Git はファイルの変更履歴を記録するバージョン管理ツールである。ローカル環境（自分の PC）内で動作し、任意のタイミングで状態を記録・復元できる。

### 2.2 Git の基本概念

#### ワークツリーとステージ（インデックス）

Git には、コミット（保存確定）までに 2 つの領域がある。

- **ワークツリー**：エディタで実際にコードを編集している作業フォルダ。
- **ステージ**：コミット対象として選択したファイルを一時的に置く準備領域。

2 段階に分かれているのは、複数ファイルを同時に編集している状況で、特定のファイルのみをひとつのコミットにまとめるためである。

#### コミット（Commit）

ステージに置いたファイルの状態を「確定して記録する」操作。コミットすると、その時点のスナップショットが固有の ID とコミットメッセージとともに履歴に刻まれる。

```bash
git add README.md            # ファイルをステージに上げる
git commit -m "first commit" # ステージの内容をコミットとして確定する
```

#### ブランチ（Branch）

開発の歴史を枝分かれさせる仕組み。本番用コード（`main`）を直接変更せず、作業用ブランチ（`feature/...`）を切って開発することで、バグが発生しても本番環境への影響を防げる。

#### プッシュ（Push）

ローカルのコミット履歴を、GitHub 等のリモートリポジトリへ同期・アップロードする操作。

### 2.3 Git のインストールと初期設定

#### インストール

**Windows：**
[Git for Windows](https://gitforwindows.org/) の公式サイトからインストーラーをダウンロードし、デフォルト設定のまま進める。

**Mac：**
ターミナルで以下を実行し、未インストールの場合は画面の指示に従う。

```bash
git --version
```

#### 初期設定（ユーザー登録）

インストール後、ターミナル（Windows は Git Bash）で以下を実行する。

```bash
git config --global user.name "ユーザー名"
git config --global user.email "メールアドレス"
```

GitHub に登録したものと合わせておくとよい。

### 2.4 GitHub リポジトリの作成と初回プッシュ

#### リポジトリの作成

1. [github.com](https://github.com/) にログインし、右上の「**＋**」から「**New repository**」をクリック。
2. **Repository name** に任意の名前を入力（例：`cicd-test`）。
3. Public / Private を選択する。「Add a README file」等の初期化オプションはすべてオフにする。
4. 「**Create repository**」を押し、表示された `https://github.com/...` の URL をコピーしておく。

#### 初回プッシュ

```bash
# 作業フォルダを作成して移動する
mkdir cicd-test
cd cicd-test

# Git の管理下に置く（初期化）
git init

# ファイルを作成してコミットする
echo "# My CI/CD Project" > README.md
git add README.md
git commit -m "first commit"

# main ブランチに名前を設定する
git branch -M main

# GitHub のリポジトリと紐付ける（URL は上でコピーしたもの）
git remote add origin [コピーした URL]

# リモートに push する
git push -u origin main
```

> **補足（作業フォルダの場所）：**  
> ターミナルを起動した直後のカレントディレクトリは通常ユーザーフォルダ（`/c/Users/ユーザー名` 等）になる。デスクトップ等の分かりやすい場所で作業したい場合は、`mkdir` の前に `cd ~/Desktop` 等で移動してから進める。  
> ドラッグ＆ドロップの裏ワザ：ターミナルに `cd ` （後ろに半角スペースを入れる）と打ち、エクスプローラーからフォルダをドラッグすると正しいパスが自動入力される。

### 2.5 push コマンドの挙動

`git push origin feature/add-dbt-setup` のようにブランチ名を 1 つだけ指定した場合、リモート側にも**同じ名前のブランチ**が対象となる。これはコロン（`:`）を省略した形であり、完全な記法は以下の通り。

```bash
git push origin feature/add-dbt-setup:feature/add-dbt-setup
#                    [ローカルの名前] : [リモートの名前]
```

ローカルとリモートで異なる名前を使いたい場合は明示的に指定する。

```bash
git push origin test-branch:feature/dbt-setup
```

引数をすべて省略した `git push` のみの場合は、Git の設定（`push.default`）に基づく。現代の Git のデフォルト（`simple`）では、現在チェックアウトしているブランチと同名のリモートブランチに push する。

---

## 3. GitHub

### 3.1 Git と GitHub の違い

| 項目 | Git（ツール） | GitHub（Web サービス） |
| --- | --- | --- |
| 場所 | ローカル PC 上 | インターネット上（クラウド） |
| 役割 | 変更履歴を記録する | 履歴を共有・保管する |
| 料金 | 完全無料 | 基本無料（高度な機能は有料） |

Git はローカルで完結するツールであり、GitHub はその履歴をネット上で共有・管理するサービスである。

### 3.2 プッシュ・プル・プルリクエストの違い

| 操作 | 方向 | 概要 |
| --- | --- | --- |
| **プッシュ（Push）** | ローカル → リモート | ローカルの変更をリモートに送信する |
| **プル（Pull）** | リモート → ローカル | リモートの最新変更をローカルに取得・統合する |
| **プルリクエスト（PR）** | — | ブランチの変更を `main` に取り込むためのレビュー依頼 |

プッシュ・プルはデータの転送操作であり、プルリクエストはチーム開発でのコードレビューと合流のためのワークフロー上のアクションである。性質が異なる。

### 3.3 Codespaces とローカル環境の使い分け

Codespaces は GitHub 上に作られた仮想 PC で、リポジトリが自動的にクローンされた状態で起動する。Git の操作やコマンド自体はローカルと同一だが、GitHub 上で動くため `git push` 時の認証が自動で行われる。

**ローカル環境が優先される理由：**

| 観点 | 内容 |
| --- | --- |
| 安定性 | インターネット接続が不安定でも作業を継続できる |
| パフォーマンス | PC のスペックをフルに使える |
| カスタマイズ性 | エディタ・ツール・設定を自由に構築できる |

**Codespaces が有効なケース：**

| ケース | 理由 |
| --- | --- |
| 新メンバーの即時オンボーディング | 環境構築不要ですぐに作業開始できる |
| 使用 PC が固定されていない | どの PC からでも同じ環境で作業できる |
| 軽微な修正 | ローカル環境を立ち上げるほどでもない変更 |

> **補足：**  
> 本研修では、stub リポジトリへの変更作業に Codespaces を使用することでローカル環境を汚さない運用を採用している。

---

## 4. Git 運用ルール

### 4.1 ブランチ戦略の基本原則

`main` ブランチで直接コードを書き換えて push することは原則禁止とする。

- **`main` ブランチ**：常に正常に動く本番用コードを置く場所。
- **`feature/...` ブランチ**：開発・修正を行う作業用ブランチ。`main` から分岐させて作成し、作業完了後に PR 経由で `main` へマージする。

### 4.2 ユースケース別ベストプラクティス

#### ケース 1：新しい作業を始める時

古いコードをベースに開発を始めると、後で push する時に衝突（競合）が起きる。`main` を最新にしてから作業ブランチを切る。

```bash
# 手元の main ブランチを最新にする
git checkout main
git pull origin main

# 作業用ブランチを作成して切り替える
git checkout -b feature/作業名

# 作業を行い、こまめにコミットする
git add .
git commit -m "変更内容の説明"
```

#### ケース 2：作業完了後にリモートへ送る時

自分の作業中にリモートの `main` が更新されている可能性があるため、push 前に rebase で取り込む。

```bash
# リモートの最新変更を自分のブランチに取り込む
git pull origin main --rebase

# main ではなく作業用ブランチを push する
git push origin feature/作業名
```

push 後は GitHub 上でプルリクエストを作成し、`main` へマージする。

#### ケース 3：作業中にブランチを切り替えたい時

未コミットの変更がある状態でブランチを切り替えようとするとエラーになる。`stash` で変更を一時退避する。

```bash
# 未コミットの変更を退避する（未追跡ファイルも含める）
git stash -u

# 別のブランチで作業する
git checkout main

# 元のブランチに戻り、退避した変更を復元する
git checkout feature/作業名
git stash pop
```

### 4.3 トラブルを防ぐ 3 つの習慣

1. **作業前に `git status` を確認する**  
   現在のブランチとコミット漏れのファイルを目視するだけで、事故の大半を防げる。

2. **`.gitignore` を設定する**  
   仮想環境フォルダ（例：`dbt/.venv/`）・秘密鍵・自動生成ファイル等は `.gitignore` に記述して Git の追跡対象から除外しておく。管理対象に入ると大量の警告や `stash` 時のロックが発生する。

3. **`git reset --hard HEAD` は慎重に使う**  
   直前のコミット状態に強制リセットするコマンド。コミットしていない変更は復元できないため、`stash` が成功していることを確認した上で実行すること。

---

## 5. Terraform

### 5.1 `terraform.tfstate`

#### 何が書かれているか

Terraform が管理するリソースの「現在の状態」が記録されている。`plan` や `apply` を実行するたびにこのファイルを参照し、「コードに書かれた状態」と「実際のリソースの状態」の差分を計算する。

#### 扱い方

| 項目 | 方針 |
| --- | --- |
| Git で管理 | **しない**（機密情報が含まれる可能性があるため） |
| 手動編集 | **しない**（破損すると全リソースが管理不能になるため） |
| 保管場所 | **HCP Terraform**（リモートステートで管理） |

### 5.2 `.terraform.lock.hcl`

#### 何が書かれているか

使用しているプロバイダー（今回は `snowflakedb/snowflake`）のバージョンとハッシュ値が記録されている。ハッシュ値はプロバイダーのバイナリが改ざんされていないことを検証するためのものである。`terraform init` を実行すると自動生成・更新される。

#### 扱い方

| 項目 | 方針 |
| --- | --- |
| Git で管理 | **する**（チーム全員が同じバージョンを使うために共有） |
| 手動編集 | **しない**（`terraform init` が自動管理） |

> **補足（両者の違い）：**  
> lock ファイルは「どのツールを使うか」を固定するもの、state ファイルは「今何が存在するか」を記録するもの。lock はコードと一緒に Git で共有し、state は HCP Terraform で管理するのがベストプラクティス。

### 5.3 Terraform が管理するオブジェクト

```
Snowflake インフラ
├── データベース（CREATE DATABASE）
├── スキーマ（CREATE SCHEMA）
├── ウェアハウス（CREATE WAREHOUSE）
├── ロール・ユーザー（CREATE ROLE / USER）
└── 権限付与（GRANT）
```

データ変換ロジックは dbt に委ねる。詳細は「[6. dbt](#6-dbt)」を参照。

### 5.4 変数解決の仕組み

#### ファイルの依存関係

```
variables.tf        → 変数を宣言する
main.tf / schema.tf → var.xxx で変数を参照する
```

#### 実行環境の遷移

```
ローカル Git → GitHub push
  → GitHub Actions が起動
  → HCP Terraform の Token を使いプラン実行を HCP Terraform に移譲
  → HCP Terraform 上で terraform plan / apply が実行される
```

#### HCP Terraform 上での値参照

HCP Terraform の実行環境において、以下のいずれかの形式で登録された値が `variables.tf` の宣言と照合されて解決される。

- **Terraform variable** として登録 → プレフィックスなし（例：`trainee_name`）
- **Environment variable** として登録 → `TF_VAR_` プレフィックス付き（例：`TF_VAR_trainee_name`）

---

## 6. dbt

### 6.1 dbt が管理するオブジェクト

```
データ変換ロジック
├── models/     ← SQL による変換・集計
├── seeds/      ← 静的マスタデータ（CSV から作成）
├── tests/      ← データ品質テスト
└── snapshots/  ← 履歴管理（SCD Type 2）
```

インフラ・権限管理は Terraform に委ねる（詳細は「[5. Terraform](#5-terraform)」を参照）。

### 6.2 Terraform と dbt の役割分担

| Terraform | dbt |
| --- | --- |
| `TF_TEST_DB` の作成 | `seeds/` でマスタデータ投入 |
| `DBT_SCHEMA` の作成 | `models/` でデータ変換 |
| ロール・ユーザーの作成 | `tests/` でデータ品質チェック |
| 権限付与（GRANT） | — |

#### CI/CD パイプラインでの実行順序

```
① terraform apply  → DB・スキーマ・権限が整う
      ↓
② dbt seed         → マスタデータが Snowflake に投入される
      ↓
③ dbt run          → マスタデータを参照してモデルが作成される
      ↓
④ dbt test         → 作成されたモデルの品質チェック
```

この順序を守ることで依存関係によるエラーを防げる。

### 6.3 `{{ ref() }}` と `{{ source() }}` の使い分け

#### `{{ ref() }}` を使う場合

同じ dbt プロジェクト内で定義されたモデルや seed を参照する場合に使用する。dbt が自動的に DB 名・スキーマ名を解決するため、静的な指定が不要になる。

```sql
SELECT
    employee_id,
    name,
    department
FROM {{ ref('EMPLOYEES') }}
ORDER BY department, employee_id
```

#### `{{ source() }}` を使う場合

dbt プロジェクト外のテーブル（Snowpipe で取り込んだ `MAILS_RAW` 等）を参照する場合に使用する。`sources.yml` での事前定義が必要。

```sql
SELECT
    employee_id,
    name,
    department
FROM {{ source('RAW', 'EMPLOYEES') }}
ORDER BY department, employee_id
```

`seeds/` 配下で定義されているテーブルは `{{ ref() }}`、Snowpipe 等で外部から投入されるテーブルは `{{ source() }}` が適切。

### 6.4 変数解決の仕組み

#### 静的方式

```
HCP Terraform 上の DBT_ENV_SECRET_DATABASE（静的文字列）
  → fetch_tfc_vars.py で取得
  → GITHUB_ENV に設定
  → dbt が参照
```

#### 動的方式（現行）

```
Terraform output（training_db_name）
  → terraform output -raw で取得
  → DBT_DATABASE として GITHUB_ENV に設定
  → dbt の profiles.yml が DBT_DATABASE を参照
```

> **補足（Python バージョン）：**  
> dbt-snowflake は **Python 3.12** が必要。Python 3.14 とは互換性がないため注意。Lambda 関数のランタイム（Python 3.14）とは別の実行環境であり、dbt の CI/CD ステップでは Python 3.12 を使用する。

---

## 7. CI/CD パイプライン

### 7.1 全体フロー（GitHub Actions → HCP Terraform → Snowflake）

```
① GitHub Actions が GitHub Secrets の TF_API_TOKEN を読み込む
      ↓
② TF_API_TOKEN で HCP Terraform に認証する
      ↓
③ HCP Terraform が Variables（Snowflake 接続情報・秘密鍵）を
   terraform 実行時に環境変数として注入する
      ↓
④ 秘密鍵による JWT 認証で Snowflake に接続し、
   terraform plan または apply を実行する
```

秘密鍵は HCP Terraform 内の sensitive 変数として隔離されており、GitHub リポジトリには一切触れない。

### 7.2 GitHub Secrets / Environments の構成

```
GitHub
  └── Organization (snowflake-training 等)
        └── Repository (snowflake_training)
              ├── Branches
              │     ├── main
              │     ├── develop
              │     └── feature/*
              │
              ├── Environments
              │     ├── ti2140
              │     │     ├── TF_WORKSPACE     = terraform-workspace
              │     │     └── HCP_WORKSPACE_ID = ws-J2rtbnPn3rAFi8yV
              │     ├── yamada
              │     │     ├── TF_WORKSPACE     = terraform-workspace-yamada
              │     │     └── HCP_WORKSPACE_ID = ws-xxxxxxxxxxxxxxxxx
              │     └── tanaka
              │           ├── TF_WORKSPACE     = terraform-workspace-tanaka
              │           └── HCP_WORKSPACE_ID = ws-yyyyyyyyyyyyyyyyy
              │
              └── Secrets / Variables（リポジトリ共通）
                    ├── HCP_API_TOKEN
                    └── DBT_ENV_SECRET_PRIVATE_KEY
```

Environments は研修生ごとに独立しており、`github.actor` をキーに対応する Environment の変数が注入される。

### 7.3 推奨ディレクトリ構成

```
プロジェクトルート
├── terraform/
│   ├── main.tf          ← DB・スキーマ・WH 作成
│   ├── schema.tf        ← ロール・ユーザー作成
│   └── variables.tf     ← 変数定義
│
└── dbt/mydbt/
    ├── models/
    │   └── mymodel/
    │       └── dbt_query.sql    ← データ変換 SQL
    ├── seeds/
    │   └── dbt_table.csv        ← マスタデータ
    └── tests/
        └── dbt_query.yml        ← データ品質テスト
```

---

## 8. AWS 環境構築

### 8.1 CloudFormation によるインフラ構築

CloudFormation の YAML テンプレートを使用してコアインフラを一括構築する。

**デプロイ手順：**

1. CloudFormation コンソールから YAML をアップロードする。
2. Parameters の入力画面で、生メール格納用バケット名を指定する。
3. 最終画面で「**IAM リソースの作成を承認する**」にチェックを入れて送信する。

**タグの付与：**  
タグはテンプレートには記述できないため、コンソールからのデプロイ時に手動で付与する。「Configure stack options」画面の Tags セクションで以下を入力する。

| Key | Value |
| --- | --- |
| Owner | 自分のユーザー名（例：trainee01） |

### 8.2 Lambda 関数の作成

#### Step 1：Lambda 関数の作成

1. AWS コンソールの検索窓で「**Lambda**」を開き、「**関数の作成**」を押す。
2. 以下を設定する。

| 項目 | 設定値 |
| --- | --- |
| 作成方法 | 一から作成 |
| 関数名 | `mail-ingest-demo`（任意） |
| ランタイム | Python 3.14 |
| アーキテクチャ | x86_64 |

> **補足（ランタイムについて）：**  
> Lambda 関数のランタイムには Python 3.14 を使用する。dbt-snowflake が必要とする Python 3.12 とは別の実行環境であり、Lambda 側のバージョン指定は dbt の CI/CD ステップに影響しない。

#### Step 2：IAM 権限の設定

Lambda が S3 からファイルを読み取るための許可を付与する。

1. Lambda の「**設定**」タブ → 「**アクセス権限**」を開く。
2. 表示された「ロール名」（青いリンク）をクリックして IAM ロール画面を開く。
3. 「**許可を追加**」→「**ポリシーをアタッチ**」を押し、`AmazonS3ReadOnlyAccess` をアタッチする。

#### Step 3：環境変数の設定

「**設定**」タブ → 「**環境変数**」→「**編集**」で以下を登録する。

| キー | 値 |
| --- | --- |
| `SNOWFLAKE_USER` | Snowflake のユーザー名 |
| `SNOWFLAKE_PASSWORD` | Snowflake のパスワード |
| `SNOWFLAKE_ACCOUNT` | Snowflake のアカウント識別子 |
| `SNOWFLAKE_DATABASE` | 使用する DB 名 |
| `SNOWFLAKE_SCHEMA` | `PUBLIC`（または使用するスキーマ名） |
| `SNOWFLAKE_WAREHOUSE` | 使用するウェアハウス名 |
| `SNOWFLAKE_TABLE` | `MAILS_RAW` |

#### Step 4：S3 トリガーの設定

1. 「**設定**」タブ → 「**トリガー**」→「**トリガーを追加**」を押す。
2. ソースとして「**S3**」を選択し、以下を設定する。

| 項目 | 設定値 |
| --- | --- |
| バケット | 手動ドロップする S3 バケット |
| イベントタイプ | すべてのオブジェクト作成イベント |

### 8.3 Lambda 依存ライブラリのパッケージング（Lambda レイヤー方式）

Lambda の実行環境には `snowflake-connector-python` が含まれていないため、パッケージングが必要。ライブラリをレイヤーとして分離することで、コードの更新時の zip サイズが小さくなり、コンソール上での動作が軽快になる。

#### Step 1：CloudShell で zip を作成する

AWS コンソール右上のプロンプトアイコン（`>_`）から CloudShell を起動し、以下を実行する。

```bash
# 作業ディレクトリの作成と移動
mkdir layer_package
cd layer_package

# Snowflake ライブラリをインストールする
python3.14 -m pip install snowflake-connector-python -t .

# ライブラリを zip 化する
zip -r snowflake_layer.zip layer_package

# ダウンロード用にパスを確認する
pwd
```

CloudShell 画面右上の「**Actions**」→「**Download file**」で、`pwd` で表示されたパスを入力して zip をダウンロードする。

**CloudShell での作業上の注意：**  
`nano lambda_function.py` 等でファイルを作成・編集する際、Python はインデントがずれると動作しない。貼り付け後に `def` や `if` 配下の字下げが正しいか確認すること。

#### Step 2：Lambda レイヤーを登録する

1. Lambda コンソールの左メニューで「**レイヤー**」を選び、「**レイヤーの作成**」を押す。
2. 以下を設定する。

| 項目 | 設定値 |
| --- | --- |
| 名前 | `snowflake-lib` |
| アップロード方法 | .zip ファイルをアップロード |
| 互換アーキテクチャ | x86_64 |
| 互換ランタイム | Python 3.14 |

#### Step 3：Lambda 関数にレイヤーを紐付ける

1. 対象の Lambda 関数を開き、画面下部の「**レイヤー**」→「**レイヤーの追加**」を押す。
2. 「**カスタムレイヤー**」を選択し、`snowflake-lib`・バージョン `1` を選んで「**追加**」をクリック。

### 8.4 Lambda 関数の実装

```python
import os
import json
import boto3
import snowflake.connector
from email import message_from_bytes
from email.policy import default

s3 = boto3.client('s3')

def lambda_handler(event, context):
    # 1. S3 から生のメールファイルを取得する
    bucket = event['Records'][0]['s3']['bucket']['name']
    key    = event['Records'][0]['s3']['object']['key']

    response          = s3.get_object(Bucket=bucket, Key=key)
    raw_email_content = response['Body'].read()

    # 2. メールを解析する（email ライブラリを使用）
    msg = message_from_bytes(raw_email_content, policy=default)

    message_id = msg.get('Message-ID') or key
    subject    = msg.get('Subject')
    sender     = msg.get('From')

    # 本文（テキストパート）を取得する
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                body = part.get_payload(decode=True).decode(
                    part.get_content_charset() or 'utf-8'
                )
                break
    else:
        body = msg.get_payload(decode=True).decode(
            msg.get_content_charset() or 'utf-8'
        )

    # 格納データを整形する
    mail_data = {
        "id":       message_id,
        "subject":  subject,
        "from":     sender,
        "body":     body,
        "file_key": key,  # デバッグ用に S3 のパスを保持する
    }

    # 3. Snowflake に接続して UPSERT する
    conn = snowflake.connector.connect(
        user      = os.environ['SNOWFLAKE_USER'],
        password  = os.environ['SNOWFLAKE_PASSWORD'],
        account   = os.environ['SNOWFLAKE_ACCOUNT'],
        warehouse = os.environ['SNOWFLAKE_WAREHOUSE'],
        database  = os.environ['SNOWFLAKE_DATABASE'],
        schema    = os.environ['SNOWFLAKE_SCHEMA'],
    )

    try:
        cursor     = conn.cursor()
        table_name = os.environ['SNOWFLAKE_TABLE']

        upsert_sql = f"""
        MERGE INTO {table_name} AS target
        USING (SELECT %s AS msg_id, %s AS content) AS src
        ON target.message_id = src.msg_id
        WHEN MATCHED THEN
            UPDATE SET target.raw_content = src.content
        WHEN NOT MATCHED THEN
            INSERT (message_id, raw_content) VALUES (src.msg_id, src.content);
        """

        cursor.execute(upsert_sql, (message_id, json.dumps(mail_data, ensure_ascii=False)))
        conn.commit()

        return {'statusCode': 200, 'body': f"Email {key} processed and upserted."}

    finally:
        conn.close()
```

**実装のポイント：**

- **メール解析**：`message_from_bytes` でバイナリデータをメールオブジェクトに変換する。
- **本文抽出**：マルチパート（HTML とテキストが混在）の場合でも `text/plain` パートを探して取得する。
- **JSON 化**：抽出した各要素を辞書にまとめ、`json.dumps` で Snowflake の `VARIANT` 型カラムに格納する。
- **外部ライブラリ**：`email`・`json`・`boto3` は Lambda 環境に標準搭載。外部インストールが必要なのは `snowflake-connector-python` のみ。

> **補足（ランタイム設定とハンドラ名）：**  
> Lambda の「コード」タブ下部にある「**ランタイム設定**」の「**ハンドラ**」欄は、デフォルトで `lambda_function.lambda_handler` になっている。`lambda_function` はファイル名（`lambda_function.py`）、`lambda_handler` は関数名（`def lambda_handler(event, context):`）を指す。ファイル名を変更した場合はこの設定も合わせて変更する。

---

## 9. Snowflake 環境構築

### Phase 0：デモ用データベースの複製と環境整備

本番環境から安全に隔離された検証用データベースとアクセス権限を整備する。

#### Step 0-1：ロールとウェアハウスの指定

```sql
USE ROLE RECRUIT_MAIL_DB_DEMO;
USE WAREHOUSE COMPUTE_WH;
```

#### Step 0-2：本番データベースのクローン

```sql
-- 本番 DB 名が「RECRUIT_MAIL_DB」の場合
CREATE OR REPLACE DATABASE RECRUIT_MAIL_DB_DEMO
  CLONE RECRUIT_MAIL_DB;
```

#### Step 0-3：デモ用テーブルの確認と作成

```sql
USE DATABASE RECRUIT_MAIL_DB_DEMO;
SHOW TABLES; -- ターゲットテーブルが存在することを確認する
```

デモ環境では `MAILS_RAW` テーブルを使用する。`message_id` が Primary Key として機能し、upsert が正しく動作するか確認する。

```sql
CREATE TABLE IF NOT EXISTS MAILS_RAW (
    message_id  VARCHAR PRIMARY KEY,  -- 重複排除のキー
    raw_content VARIANT,              -- メール全文（JSON）を格納
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

### Phase 2：Snowflake–AWS 間の接続設定（Storage Integration）

#### Step 2：Storage Integration の作成（Snowflake）

Snowflake 側で、新 S3 バケットの `messages/` パスを許可した `STORAGE INTEGRATION` オブジェクトを SQL で作成する。作成後、`DESCRIBE INTEGRATION` を実行して Snowflake 側が発行した「AWS 用アカウント ID」と「External ID」をメモする。

#### Step 3：Snowflake 用 IAM ロールの作成（AWS）

1. IAM コンソールで新規 IAM ロールを作成する。
2. **信頼関係タブ**：Step 2 でメモした Snowflake の ID と External ID を JSON に貼り付ける。
3. **許可タブ**：CloudFormation で作成した S3 バケットの `messages/*` に対する `GetObject`・`ListBucket` 等の最小権限ポリシーを付与する。

#### Step 4：IAM ロール ARN の紐付け（Snowflake）

Step 3 で完成した IAM ロールの ARN を Snowflake 側の Storage Integration オブジェクトに `ALTER` 命令で紐付ける。これで両者の接続が確立する。

### Phase 3：Snowpipe の構築

#### Step 8：ステージ（Stage）の作成

Storage Integration と新 S3 バケットの URL（`s3://[バケット名]/messages/`）を指定して外部ステージを作成する。

#### Step 9：Snowpipe の作成

Step 8 のステージを監視し、データが届いたらターゲットテーブルに `COPY INTO` する `PIPE` オブジェクトを作成する。作成後、`SHOW PIPES` を実行して Snowpipe が自動生成した **SQS の ARN** をコピーする。

#### Step 10：S3 イベント通知の設定

CloudFormation で作成した S3 バケットの「プロパティ」→「イベント通知」を開き、以下を設定する。

| 項目 | 設定値 |
| --- | --- |
| プレフィックス | `messages/` |
| サフィックス | `.jsonl` |
| イベントタイプ | ObjectCreated |
| 送信先 | SQS（Step 9 でコピーした Snowpipe の SQS ARN） |

### 9.1 Snowpipe の仕組み

Snowpipe は S3 等の外部ストレージにファイルが作成されたことを検知し、サーバーレスで即座に Snowflake へデータを取り込む機能。

#### S3 → SQS → Snowpipe の流れ

1. S3 バケットの特定フォルダにファイルが保存されると、S3 のイベント通知機能が作動する。
2. S3 が「ファイルができた」というメッセージを Snowflake が管理する SQS キューに送信する。  
   （SQS は Snowflake 側が自動的に用意するため、AWS 側でユーザーが SQS を作成する必要はない。）
3. Snowpipe が SQS をポーリングし、通知が届くとファイルパスを取得して取り込みを実行する。

#### 重複排除

Snowpipe はロード済みのファイル名を「ロード履歴（Load History）」として保持しており、同じファイルが通知されても二重に取り込まない。この履歴はデフォルトで 14 日間保持される。

#### コンピューティングとコスト

Snowpipe はユーザーが作成した仮想ウェアハウスを使用しない。Snowflake が管理するサーバーレスリソースで `COPY INTO` を実行し、取り込んだデータ量に応じてサーバーレス料金として課金される。

| 項目 | 内容 |
| --- | --- |
| トリガー | S3 から Snowflake 管理の SQS へのイベント通知 |
| コンピューティング | Snowflake 管理のサーバーレスリソース（自前ウェアハウス不要） |
| 信頼性 | ファイル名ベースのメタデータ管理により重複を自動排除 |
| 適した用途 | 小規模なファイルが継続的・頻繁に届くケース |

#### ステータス確認

Snowpipe は非同期で動作するため、実行結果はその場で返ってこない。状態確認には専用関数を使用する。

- `SYSTEM$PIPE_STATUS`：パイプが正常に動作しているか、SQS から通知を受け取っているか確認する。
- `VALIDATE_PIPE_LOAD`：過去 14 日間の取り込み履歴とエラー有無を確認する。

### 9.2 Stream / Task による正規化パイプライン

#### 工程 A：Stream の作成

`MAILS_RAW` テーブルへの新規データ投入を検知するための `STREAM` オブジェクトを作成する。Task が「新着分のみ」を効率的に処理できるようになる。

#### 工程 B：ストアドプロシージャの実装

`MAILRULE_EXTRACTION_STRATEGY.md` に定義された抽出ルール（`job_score`・`candidate_score` によるカテゴリ判定等）に基づき、以下の処理を実装する。

1. `BODY_TEXT` からキーワードを抽出する。
2. カテゴリを判定する（`job` / `candidate` / `other`）。
3. 判定結果に応じて `JOBS` または `CANDIDATES` テーブルへデータを振り分ける。

#### 工程 C：Task の作成

工程 B のプロシージャを定期的に、あるいは Stream にデータがある時にのみ実行するスケジュールを設定し、`RESUME` で起動する。

### Phase 4：試験

`.eml` ファイルを S3 バケットの `raw_emails/` に手動でアップロードし、以下を確認する。

- AWS Lambda が自動起動してログを出力しているか。
- S3 の `messages/` に日付フォルダが作成されて `.jsonl` ファイルが配置されているか。
- Snowflake のテーブルに数秒〜数十秒後にレコードが追加されているか。