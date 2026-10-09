# リリースノート

App Store Connectの「このバージョンの新機能」欄に貼る文面と、申請時の手順を記録します。

## 1.1（ビルド9、2026-10-09審査提出）

`PenPhoto/Info.plist` を `CFBundleShortVersionString = 1.1` / `CFBundleVersion = 9` に更新済みです（ピンチズームを加えたTestFlight確認用に8から上げました）。
1.0（2026-09-17公開）からの利用者に見える変更は、写真の左回転の追加、「ことば」を追加したときの入力欄の扱い、カメラのピンチズームです。
トリミング・ビューティー・カメラプレビューの改善は2026-09-12のコミットに含まれ、1.0のビルドに入っています。

### ストア掲載文（日本語、コピー用）

```
写真の回転を左右どちらにも行えるようにしました。

・90度回転が右だけでなく左にも対応しました。
・「ことば」画面の上部と「写真・ビューティー」タブの両方から操作できます。
・文字を入力している最中でも回転でき、取り消し・やり直しの対象になります。

「ことば」を追加すると、入力欄は薄い字の「ひとこと」を表示するだけになりました。書き始める前に消す必要はありません。

カメラの画面をピンチして拡大・縮小できるようになりました。
```

### 申請前チェック

- [x] ビルド9が1.0の公開ビルド（7）より大きいこと。App Store Connect APIで確認（2026-10-09）。
- [x] 単体テスト・UIテストが成功していること（docs/VERIFICATION.md に結果を記録）。
- [x] 実機で左右回転・取り消し・やり直しを確認していること（iPhone 12 mini / iPhone 16eで実施済み）。
- [x] TestFlightのビルド9で、ピンチズーム（スライダーとの連動、ピンチ直後のタップでのピント合わせ）を実機確認していること。
- [x] スクリーンショットの差し替えが必要か判断する。編集画面の2枚（01-editor、03-crop-applied）を左回転ボタン入りの画面に差し替えた。02-crop-editorは変更なし。
- [x] 年齢制限、プライバシー（データ収集なし）、カテゴリ、価格（無料）、配信地域（日本）は1.0から変更なし。

### アップロード手順（Xcode）

このMacには配布用証明書（Apple Distribution）がなく、XcodeのApple IDサインインも切れています。
CLIからのアーカイブは開発用証明書が選ばれてしまい、App Storeへは提出できません。次の手順で行います。

1. Xcode > Settings > Accounts でApple IDを追加し、チーム「TAKU MATSUMURA（YY9Y6VAGJY）」を選ぶ。
2. 「Manage Certificates」でApple Distribution証明書を作成する（無い場合は「+」から）。
3. ログインキーチェーンを解錠しておく（施錠されていると `codesign` が `errSecInternalComponent` で失敗する）。
4. Schemeの実行先を「Any iOS Device (arm64)」にし、Product > Archive を実行する。
5. Organizerで対象アーカイブを選び、Distribute App > App Store Connect > Upload。
6. App Store Connectで「+ バージョン」から1.1を作成し、上のストア掲載文を貼り、アップロードしたビルドを選んで審査に提出する。

証明書作成後であれば、CLIからのアーカイブとアップロードも可能になります。
App Store Connect APIキー（.p8 / Key ID / Issuer ID）を用意する場合は `xcodebuild -exportArchive` と `xcrun notarytool`／`altool` で自動化できます。

## 1.0（ビルド番号不明、2026-09-17公開）

初回公開。ストアページ：https://apps.apple.com/jp/app/penphoto/id6811245656
公開時のリリースノートはApple提供のメタデータに含まれておらず、内容は記録していません。
