# bluetooth-distance-measurement
flutter_blue_plusを用いて周辺機器のRSSI値とTxPowerを取得し、特定機器との距離を測定するデモアプリケーションです。

### 開発環境セットアップ
本プロジェクトは、Android Studio上のFlutterプロジェクトで動作するデモアプリケーションです。したがって、事前にAndroid StudioとFlutter SDKをインストールする必要があります。

- [Android Studio](https://developer.android.com/studio?hl=ja)
- [Flutter SDK](https://docs.flutter.dev/install/archive)

### プロジェクトのインポート方法
Android Studioを起動したら、起動画面（またはFileメニュー）から、OpenまたはOpen an existing projectを選択します。インストールした本プロジェクトのルートディレクトリを選択し、プロジェクトを開きます。

### パッケージのインストール
必要なパッケージをインストールします。
```bash
flutter pub get
```

### 本プロジェクトに含まれる依存関係
本プロジェクトには、以下の依存関係が含まれます。
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^1.5.0
  permission_handler: ^11.0.1
```

### mainプログラムの実行
Android実機をUSB接続します（USBデバッグを有効にしておく）。Android Studio上のエミュレータでは、Bluetooth機能が使用できないので注意してください。デバイスが接続されたらmain.dartを実行します。
