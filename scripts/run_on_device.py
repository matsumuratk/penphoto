#!/usr/bin/env python3
"""Build, sign, install and launch PenPhoto on a paired physical iPhone."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build-physical'


def run(command, **kwargs):
    print('+ ' + ' '.join(map(str, command)), flush=True)
    return subprocess.run([str(part) for part in command], cwd=ROOT, check=True, **kwargs)


def devices():
    with tempfile.TemporaryDirectory(prefix='penphoto-devices-') as temporary:
        output = Path(temporary) / 'devices.json'
        run(['xcrun', 'devicectl', 'list', 'devices', '--timeout', '30', '--json-output', output])
        data = json.loads(output.read_text())
        return [device for device in data.get('result', {}).get('devices', [])
                if device.get('hardwareProperties', {}).get('platform') == 'iOS'
                and device.get('hardwareProperties', {}).get('reality') == 'physical']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='Device identifier or UDID; auto-selects only when one iPhone is paired.')
    parser.add_argument('--list', action='store_true', help='List devices without building or installing.')
    parser.add_argument('--build-only', action='store_true', help='Produce a signed app without installing.')
    parser.add_argument('--skip-build', action='store_true', help='Install the previously built, signed app.')
    parser.add_argument('--no-launch', action='store_true', help='Install without opening the app.')
    args = parser.parse_args()
    if args.build_only and args.skip_build:
        parser.error('--build-only and --skip-build cannot be combined')
    if args.list:
        devices()
        return
    device_id = args.device
    if not args.build_only and not device_id:
        candidates = devices()
        if len(candidates) != 1:
            raise RuntimeError('対象のiPhoneを --device <Identifier> で指定してください。接続確認は --list を使います。')
        device_id = candidates[0]['identifier']
    if not args.skip_build:
        BUILD.mkdir(exist_ok=True)
        command = ['xcodebuild', '-project', 'PenPhoto.xcodeproj', '-scheme', 'PenPhoto',
                   '-configuration', 'Debug', '-destination', 'generic/platform=iOS',
                   '-derivedDataPath', BUILD, '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration', 'build']
        log = BUILD / 'device-build.log'
        print(f'実機向けに署名してビルドします。ログ: {log}', flush=True)
        with log.open('w') as stream:
            try:
                run(command, stdout=stream, stderr=subprocess.STDOUT)
            except subprocess.CalledProcessError:
                print('\n'.join(log.read_text(errors='replace').splitlines()[-50:]), file=sys.stderr)
                raise RuntimeError('署名ビルドに失敗しました。Config/Signing.local.xcconfig のTeamとXcodeのApple Accountを確認してください。')
    app = BUILD / 'Build/Products/Debug-iphoneos/PenPhoto.app'
    if not app.exists():
        raise RuntimeError('署名済みアプリがありません。--skip-build を外して実行してください。')
    run(['codesign', '--verify', '--deep', '--strict', app])
    if not (app / 'embedded.mobileprovision').exists():
        raise RuntimeError('開発用プロビジョニングがありません。署名設定を確認してください。')
    if args.build_only:
        print(f'署名済みアプリを作成しました: {app}')
        return
    run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', device_id, '--timeout', '120', app])
    print('iPhoneへインストールしました。', flush=True)
    if not args.no_launch:
        with (app / 'Info.plist').open('rb') as stream:
            bundle = plistlib.load(stream)['CFBundleIdentifier']
        run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', device_id, '--timeout', '60', bundle])
        print('PenPhotoを起動しました。カメラの許可を確認して撮影してください。')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f'\n実機実行を完了できませんでした: {error}', file=sys.stderr)
        print('iPhoneのUSB接続・ロック解除・このMacへの信頼・デベロッパモードを確認してください。詳細: docs/DEVICE_TESTING.md', file=sys.stderr)
        sys.exit(1)
