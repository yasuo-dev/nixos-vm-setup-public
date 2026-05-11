# nixos-vm-setup-public

NixOS 開発用 VM を再現性高くセットアップするための、公開用 bootstrap スクリプトとテンプレート集です。

## 概要

このリポジトリは、NixOS ベースの仮想マシンを初期セットアップするための公開用スクリプトを管理するためのものです。

メインスクリプトである `bootstrap-install.sh` は、NixOS Live ISO 環境上で実行することを想定しています。

このスクリプトは、NixOS の第1段階インストールを行い、再起動後にホストOSから SSH 接続できる最小構成の NixOS VM を作成します。

このリポジトリには、公開して問題ない汎用的なセットアップ処理のみを含めます。

秘密情報、private リポジトリの URL、アクセストークン、age key、秘密鍵、マシン固有の設定などは、このリポジトリには含めないでください。

## メインスクリプト

### `bootstrap-install.sh`

`bootstrap-install.sh` は、NixOS の初回インストール用 bootstrap スクリプトです。

主に以下の処理を行います。

- 必須パラメータの検証
- EFI / BIOS ブートモードの判定
- ネットワークインターフェースの自動検出、または指定
- 指定ディスクのパーティション作成
- root パーティションのフォーマット
- EFI ブート時の EFI パーティション作成・フォーマット・マウント
- `nixos-generate-config` による初期設定生成
- 最小構成の `configuration.nix` 生成
- 通常ユーザーの作成
- SSH 公開鍵認証の有効化
- SSH パスワードログインの無効化
- `nixos-install` による NixOS インストール

インストール後に再起動すると、ホストOSから SSH 接続できる状態になります。

## 想定用途

このスクリプトは、主に以下のような仮想環境での利用を想定しています。

- UTM
- Proxmox
- ローカル開発用 VM
- 使い捨ての NixOS 検証環境
- 再現性のある開発環境

その他の環境でも動作する可能性はありますが、主な対象は NixOS VM の初期セットアップです。

## インストールの流れ

想定しているセットアップの流れは以下です。

```text
NixOS Live ISO
  ↓
bootstrap-install.sh を実行
  ↓
対象ディスクをパーティション作成・フォーマット
  ↓
最小構成の NixOS 設定を生成
  ↓
nixos-install を実行
  ↓
再起動
  ↓
SSH で接続
  ↓
private 設定などの次段階へ進む
```

このリポジトリが担当するのは、公開可能な第1段階インストール部分です。

private 設定や secrets は、別の private リポジトリや安全なプロビジョニング手順で扱う想定です。

## 警告

> [!WARNING]
> このスクリプトは破壊的なディスク操作を行います。

`bootstrap-install.sh` は、指定されたディスクをパーティション作成・フォーマットします。

対象ディスク上の既存データはすべて削除されます。

実行前に、必ず対象ディスクを確認してください。

対象ディスクの例:

```text
/dev/sda
/dev/vda
/dev/nvme0n1
```

実行前に `lsblk` で確認することを推奨します。

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,MODEL
```

## 必要条件

このスクリプトは、NixOS Live ISO 環境上で実行することを想定しています。

主に以下のコマンドを使用します。

- `bash`
- `curl`
- `ip`
- `lsblk`
- `sgdisk`
- `wipefs`
- `partprobe`
- `udevadm`
- `mkfs.ext4`
- `mkfs.fat`
- `mount`
- `umount`
- `nixos-generate-config`
- `nixos-install`

これらは通常、NixOS インストーラー環境で利用可能です。

## 基本的な使い方

### 例: GitHub の公開 SSH key を使う場合

```bash
curl -fsSL https://raw.githubusercontent.com/yasuo-dev/nixos-vm-setup-public/main/scripts/bootstrap-install.sh -o bootstrap-install.sh
chmod +x ./bootstrap-install.sh
sudo bash ./bootstrap-install.sh \
  --user user-dev \
  --host nixos-utm-dev \
  --ip 192.168.64.50 \
  --gateway 192.168.64.1 \
  --dns 1.1.1.1 \
  --disk /dev/vda \
  --ssh-key-url "https://github.com/YOUR_GITHUB_USERNAME.keys" \
  --yes-i-really-mean-it
```

### 例: 標準入力から SSH 公開鍵を渡す場合

```bash
cat ~/.ssh/id_ed25519.pub | ssh nixos@192.168.64.xxx 'sudo bash ./bootstrap-install.sh \
  --user user-dev \
  --host nixos-utm-dev \
  --ip 192.168.64.50 \
  --gateway 192.168.64.1 \
  --dns 1.1.1.1 \
  --disk /dev/vda \
  --ssh-key-stdin \
  --yes-i-really-mean-it'
```

### 例: Live ISO 環境上の SSH 公開鍵ファイルを使う場合

```bash
sudo bash ./bootstrap-install.sh \
  --user user-dev \
  --host nixos-utm-dev \
  --ip 192.168.64.50 \
  --gateway 192.168.64.1 \
  --dns 1.1.1.1 \
  --disk /dev/vda \
  --ssh-key-file ./id_ed25519.pub \
  --yes-i-really-mean-it
```

## オプション

```text
--user USER                 作成するユーザー名
--host HOSTNAME             NixOS のホスト名
--ip IP_ADDRESS             静的 IPv4 アドレス
--gateway GATEWAY           デフォルトゲートウェイ
--dns DNS_SERVER            DNS サーバー
--disk DISK                 インストール対象ディスク

--ssh-key-url URL           SSH 公開鍵を取得する URL
--ssh-key-file FILE         NixOS Live 環境上の SSH 公開鍵ファイル
--ssh-key-stdin             標準入力から SSH 公開鍵を読み込む

--iface IFACE               ネットワークインターフェース名
--prefix PREFIX             IPv4 prefix length。デフォルト: 24
--timezone TIMEZONE         タイムゾーン。デフォルト: Asia/Tokyo
--locale LOCALE             デフォルトロケール。デフォルト: en_US.UTF-8
--state-version VERSION     NixOS stateVersion。デフォルト: 25.05
--boot-mode MODE            auto, efi, bios のいずれか。デフォルト: auto

--yes-i-really-mean-it      破壊的ディスク操作を許可するために必須
--help                      ヘルプを表示
```

## 生成される初期設定

生成される NixOS 設定には、以下が含まれます。

- 静的 IPv4 ネットワーク設定
- OpenSSH の有効化
- SSH 公開鍵認証の有効化
- SSH パスワードログインの無効化
- root の SSH ログイン無効化
- ファイアウォール有効化
- TCP 22番ポートの許可
- `wheel` グループに所属する通常ユーザー
- 一時的なローカルコンソール用パスワード: `changeme`
- 基本パッケージ:
  - `git`
  - `curl`
  - `wget`
  - `vim`
  - `nano`
  - `openssh`
  - `htop`
  - 各種アーカイブユーティリティ

また、Nix の experimental features として以下を有効化します。

```nix
nix-command
flakes
```

## インストール後

VM を再起動します。

```bash
reboot
```

その後、ホストOSから SSH 接続します。

```bash
ssh user-dev@192.168.64.50
```

SSH config の例:

```sshconfig
Host nixos-utm-dev
  HostName 192.168.64.50
  User user-dev
  IdentityFile ~/.ssh/id_ed25519_nixos
  IdentitiesOnly yes
```

初回ログイン後、一時パスワードを変更してください。

```bash
passwd
```

## セキュリティ上の注意

このリポジトリには secrets を含めないでください。

コミットしてはいけないもの:

- SSH 秘密鍵
- GitHub Personal Access Token
- age identity key
- `.env` ファイル
- private リポジトリの URL
- 本番用設定

推奨する分離方針:

```text
public repository
  bootstrap scripts
  reusable templates

private repository
  actual machine configuration
  private flake
  deployment-specific settings
```

## このリポジトリの役割

このリポジトリは、公開可能な bootstrap セットアップ専用です。

完全な private NixOS 設定リポジトリではありません。

想定している多段階構成は以下です。

```text
Stage 0:
  NixOS Live ISO を起動

Stage 1:
  この公開リポジトリの bootstrap-install.sh を実行

Stage 2:
  flakesなどを使って本格的な NixOS 設定を適用
```

## ライセンス

このプロジェクトは MIT License で公開します。
