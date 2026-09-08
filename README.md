# PenPhoto

写真を撮り、日本語の手書き風コメントを添えて残すiPhoneアプリの開発版です。
SwiftUI / AVFoundation / Vision / Core Image / PhotoKit。外部パッケージ、APIキー、バックエンドは不要です。

## 起動方法

1. `PenPhoto.xcodeproj` をXcodeで開きます。
2. Schemeで `PenPhoto`、実行先でiPhoneシミュレータを選び、Runします。
3. 「サンプルで編集を試す」または「読み込む」から編集できます。
4. 実機で使う場合は、iPhoneをUSB接続してロックを解除し、Xcodeで実行先にiPhoneを選んでRunします。このMacの開発Teamはローカル設定済みです。[実機検証手順](docs/DEVICE_TESTING.md)を参照してください。

対応：iOS 17.0以上、iPhone。画面UIは縦向き、撮影データは端末の縦横の向きを反映します。
カメラ撮影は実機が必要です。`python3 scripts/run_on_device.py` でも署名ビルド・インストール・起動できます。

## 実装した機能

- 16:9では左右余白・角丸・ヘッダーを外した全幅ファインダーと、白いシャッター／半透明の操作エリアを表示
- 撮影比率4:3／16:9の切り替えと選択の保持（縦持ちでは3:4／9:16）。プレビューと完成画像を同じ中央範囲に切り抜き
- 写真撮影、前後カメラ切替、デジタルズーム、フラッシュON/OFF、タップでピントと露出位置の指定
- 露出補正、3秒タイマー、グリッド
- ビューティーON/OFFと強度。顔ランドマークを使った部分平滑化と明るさ補正の試作
- ビューティープレビュー（約6fpsを上限に640pxへ縮小処理）と保存時の高解像度処理
- 写真の読み込み（PhotosPicker）
- 日本語手書きフォントYomogi、最大8コメント、1コメント200文字まで
- コメントの移動、ピンチ拡大、色、サイズ、傾き、半透明背景、取り消し・やり直し
- 明るさ、90度回転、中央基準の1:1 / 4:5 / 16:9トリミング
- コメントを画像の画素へ合成して写真アプリに保存、標準の共有シート
- アプリ内の下書き、マイフォトからの再編集
- 編集を閉じる際の未保存確認、保存権限拒否・読み込み／書き込みエラーの表示

## 保存仕様

`Application Support/PenPhoto/<UUID>/` に次を保存します。

- `original.jpg`: 編集前の画像。初回のみJPEG品質0.98で保存し、再編集で上書きしません。
- `recipe.json`: コメント本文・相対位置・装飾・補正設定
- `thumbnail.jpg`: マイフォト用サムネイル

アプリ内の元画像は読み込んだファイルそのもののバイト列ではなく、JPEGへの変換保存です。RAW、HDR、元のEXIF／位置情報等の完全保持には未対応です。
写真アプリへの書き出しは文字を合成した別画像です。写真アプリ内のその画像だけから文字を再編集することはできません。
写真の追加権限が拒否されても、先に保存した下書きはマイフォトから開けます。
アプリを削除すると下書きも削除されます。残す写真は写真アプリにも保存してください。
アプリが写真を外部サーバーへ送信する処理はありません。OSのバックアップや写真の同期は端末の設定に従います。

## 現時点の制限

初回の動作検証用実装であり、Apple純正カメラ相当の全機能や商用公開を完了した版ではありません。

- 超広角／望遠のレンズ選択、動画、Live Photos、RAW、深度ポートレート、ナイトモード等は未実装。
- 美肌処理は顔の楕円領域から目・眉・口を除外する近似です。皮膚セグメンテーションではなく、髪・鼻・背景を完全には分離しません。顔の形状変更は行いません。
- プレビューと高解像度写真では顔検出結果・細部の見え方に差が出る可能性があります。実機の品質・発熱・フレーム速度は未検証です。
- トリミングは中央固定。切り抜き範囲のドラッグ、自由手描き、文字の縁取り、追加フォントは後続対応。
- 写真を回転／トリミングした場合、コメントは変更後の写真に対する相対位置に維持されます。
- 写真の端へ文字を移動すると、はみ出した部分は画面と書き出しの両方で切り取られます。
- 大容量の写真（48MP等）のメモリ評価、バックグラウンド中の編集復旧、下書き削除・検索・同期、アクセシビリティの全項目監査は未完了。
- App Store申請、配布用署名、プライバシー申告、ストア用画像は未実施。

## ビルド・テスト

```sh
xcodebuild -project PenPhoto.xcodeproj -scheme PenPhoto \
  -sdk iphonesimulator -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

xcodebuild -project PenPhoto.xcodeproj -scheme PenPhoto \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

`PenPhotoTests`: 日本語フォント、編集情報の往復、文字の画素合成、回転、中央トリミング、顔なし時の処理、元写真を保持した再保存を検証。
`PenPhotoUITests`: サンプルを開き、コメント編集・下書き保存・再編集・写真への書き出しを検証。

Swiftファイルやリソースを追加した場合は `python3 scripts/generate_project.py` でプロジェクトを再生成できます。署名設定は `Config/Signing.local.xcconfig` に保存することで再生成後も保持されます。

## 検証結果

シミュレータ／実機向け（署名なし）のビルド成功。単体テスト11件とUIテスト2件が成功しました。画面と確認範囲は [検証記録](docs/VERIFICATION.md) に記載しています。

## 実機で次に確認すること

- 前後カメラ、縦横撮影、フラッシュ有無、ズーム、ピント、露出、タイマー中のアプリ中断
- カメラ／写真保存の権限拒否と設定変更からの復帰
- 顔なし・一人・複数人、暗所／逆光、肌色の違い、眼鏡、髪と背景の境界
- プレビューと保存結果の比較、連続撮影時の発熱・メモリ・待ち時間
- 小型画面、キーボード表示、日本語の長文・改行・絵文字、VoiceOver
- 容量不足時に既存の元写真と編集情報が保たれること

## フォント

[Yomogi / Google Fonts](https://github.com/google/fonts/tree/main/ofl/yomogi)、SIL Open Font License 1.1。
フォントとライセンスを `PenPhoto/Resources/` に同梱しています。アプリの設定画面からもライセンスを確認できます。

参考：[Apple AVCam](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)、[Vision](https://developer.apple.com/documentation/vision)、[PHAssetChangeRequest](https://developer.apple.com/documentation/photos/phassetchangerequest)。
