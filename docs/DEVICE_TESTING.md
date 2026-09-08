# iPhoneでPenPhotoを検証する

## このMacでの準備

`Config/Signing.local.xcconfig` に確認済みの開発Teamを設定済みです。
`Config/Signing.xcconfig` がこれを読み込み、アプリとテストに自動署名を適用します。
ローカル署名設定はGit管理対象外です。プロジェクトの再生成では消えません。

## Xcodeから実行する

1. iPhoneをMacにUSB接続し、ロックを解除します。iPhoneに「このコンピュータを信頼」が出た場合は許可します。
2. `PenPhoto.xcodeproj` を開きます。
3. 上部のSchemeは `PenPhoto`、実行先は接続したiPhoneを選びます。
4. Run（⌘R）でビルド・インストール・起動します。
5. 初回のカメラ利用確認を許可し、写真を撮ります。保存時の写真追加確認も許可してください。

iPhone側のデベロッパモードがオフの場合は、「設定 → プライバシーとセキュリティ → デベロッパモード」を有効にし、案内に沿って再起動・確認します。
このMacで確認したiPhone 16eはデベロッパモードが有効でした。

## ターミナルから実行する

プロジェクトフォルダで実行します。

```sh
python3 scripts/run_on_device.py
```

ペアリング済みの対象が1台なら自動選択し、署名ビルド → インストール → 起動を行います。
複数ある場合は対象を明示してください。

```sh
python3 scripts/run_on_device.py --list
python3 scripts/run_on_device.py --device '<IdentifierまたはUDID>'
```

オプション：

- `--build-only`: 署名済みアプリを作成するところまで。
- `--skip-build`: 直前に作ったアプリをインストールする。コード変更後は指定しないこと。
- `--no-launch`: インストールだけ行い、起動はiPhoneのアイコンから行う。

ビルド出力は `build-physical/`、スクリプトのビルドログは `build-physical/device-build.log` です。
初回はAppleの開発用プロビジョニング更新のためにネットワーク接続が必要です。

## 別のMac・別のTeamで実行する場合

1. XcodeのSettings → Apple Accountsに自分のApple Accountを追加します。
2. `Config/Signing.local.xcconfig.example` を `Config/Signing.local.xcconfig` にコピーします。
3. `DEVELOPMENT_TEAM` に自分のTeam IDを設定します。
4. Bundle Identifierを自分のTeamで利用できない場合のみ、`PENPHOTO_BUNDLE_IDENTIFIER` を独自の値へ変更します。
5. Xcodeまたは上記スクリプトから実行します。

署名情報を直接Xcodeのターゲット設定に上書きすると、xcconfigより優先されます。Team／Bundle IDの変更はローカルxcconfigにまとめると再生成後も維持できます。

## うまく動かない場合

| 状況 | 対応 |
| --- | --- |
| iPhoneが出てこない／接続失敗 | USB接続・ロック解除・Macへの信頼を確認。XcodeのWindow → Devices and Simulatorsで状態を確認 |
| 開発者ディスクイメージをマウントできない | ロック解除して再接続。Xcodeのデバイス準備が完了するまで待つ。継続する場合はiPhoneのOSに対応するXcode／デバイスサポートを確認 |
| Team／プロファイルのエラー | ローカルxcconfigのTeam、XcodeのApple Accountへのログイン、ネットワークを確認 |
| 起動時に未信頼の開発者と表示 | iPhoneの設定 → 一般 → VPNとデバイス管理に対象の開発者が表示されている場合、信頼設定を行う |
| カメラが真っ黒 | iPhoneの設定でPenPhotoのカメラ権限を確認。ほかのカメラ利用アプリを閉じ、再開する |
| 写真への保存を拒否した | 下書きはマイフォトに保存済み。iPhoneの設定で写真追加を許可して再保存 |

## 最初の10分で確認する項目

- [ ] 撮影画面上部の「4:3」を押して「16:9」に切り替える。縦持ちでは9:16、横持ちでは16:9の写真として保存される
- [ ] 16:9で左右いっぱいに表示され、上部の比率切替・タイマー・グリッドと下部のシャッターを操作できる
- [ ] 16:9のプレビューと保存写真で写る範囲が一致し、マイフォトから開き直しても比率が保持される
- [ ] 背面で撮影 → 日本語コメントを入力 → 写真に保存できる
- [ ] 写真アプリで開いてもコメントが表示される
- [ ] マイフォトからコメントを書き直して、別の完成画像を保存できる
- [ ] 前面カメラでも撮影できる。プレビューと保存写真の左右が意図どおり
- [ ] 縦・横撮影で保存写真の向きと文字の位置が正しい
- [ ] ズーム、ピント、露出、フラッシュ、タイマー、グリッドを操作できる
- [ ] ビューティーを0／中／最大で比較し、目・眉・口や髪が不自然にならない
- [ ] 顔なし・複数人でも撮影が止まらない
- [ ] アプリを一度離れ、戻って撮影できる
- [ ] 連続使用時の待ち時間、発熱、強制終了の有無を確認する

[Appleの実機実行手順](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
[Appleのデベロッパモード説明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
