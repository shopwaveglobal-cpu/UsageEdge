#!/usr/bin/env python3
"""Opt-in setup of the Claude Code status line, without overwriting an existing one."""
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile


def install(settings_path):
    settings_path = Path(settings_path)
    if settings_path.is_symlink():
        raise ValueError('설정 파일이 심볼릭 링크여서 자동 변경하지 않았습니다.')
    original = settings_path.read_bytes() if settings_path.exists() else None
    try:
        settings = json.loads(original) if original is not None else {}
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError('설정 파일을 읽을 수 없어 변경하지 않았습니다.') from exc
    source = Path(__file__).resolve().with_name('claude_status.py')
    if not source.is_file():
        raise ValueError('상태줄 스크립트를 찾을 수 없습니다.')
    script = settings_path.parent / 'usageedge' / 'claude_status.py'
    desired = {'type': 'command', 'command': 'python3 ' + shlex.quote(str(script))}
    if not isinstance(settings, dict):
        raise ValueError('지원하지 않는 설정이 있어 변경하지 않았습니다.')
    if 'statusLine' in settings and settings['statusLine'] != desired:
        raise ValueError('기존 상태줄이 있어 변경하지 않았습니다.')
    settings_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if script.parent.is_symlink() or script.is_symlink():
        raise ValueError('연결 도구 경로가 심볼릭 링크여서 변경하지 않았습니다.')
    script.parent.mkdir(mode=0o700, exist_ok=True)
    fd, helper_temp = tempfile.mkstemp(prefix='.usageedge-helper-', dir=script.parent)
    try:
        with os.fdopen(fd, 'wb') as file:
            file.write(source.read_bytes())
        os.replace(helper_temp, script)
    finally:
        if os.path.exists(helper_temp): os.unlink(helper_temp)
    if settings.get('statusLine') == desired:
        return
    settings['statusLine'] = desired
    fd, temp = tempfile.mkstemp(prefix='.usageedge-settings-', dir=settings_path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            json.dump(settings, file, ensure_ascii=False, indent=2)
            file.write('\n')
        current = settings_path.read_bytes() if settings_path.exists() else None
        if settings_path.is_symlink() or current != original:
            raise ValueError('설정 파일이 변경되어 설치를 중단했습니다.')
        os.replace(temp, settings_path)
    finally:
        if os.path.exists(temp): os.unlink(temp)


def uninstall(settings_path):
    settings_path = Path(settings_path)
    if settings_path.is_symlink():
        raise ValueError('설정 파일이 심볼릭 링크여서 변경하지 않았습니다.')
    if not settings_path.exists():
        return
    original = settings_path.read_bytes()
    try:
        settings = json.loads(original)
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError('설정 파일을 읽을 수 없어 변경하지 않았습니다.') from exc
    if not isinstance(settings, dict):
        raise ValueError('지원하지 않는 설정입니다.')
    if 'statusLine' not in settings:
        return
    script = settings_path.parent / 'usageedge' / 'claude_status.py'
    desired = {'type': 'command', 'command': 'python3 ' + shlex.quote(str(script))}
    if settings['statusLine'] != desired:
        raise ValueError('다른 상태줄이 있어 변경하지 않았습니다.')
    del settings['statusLine']
    fd, temp = tempfile.mkstemp(prefix='.usageedge-settings-', dir=settings_path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            json.dump(settings, file, ensure_ascii=False, indent=2)
            file.write('\n')
        if settings_path.is_symlink() or not settings_path.exists() or settings_path.read_bytes() != original:
            raise ValueError('설정 파일이 변경되어 해제를 중단했습니다.')
        os.replace(temp, settings_path)
    finally:
        if os.path.exists(temp): os.unlink(temp)


def main():
    if sys.argv[1:] not in (['--install'], ['--uninstall']):
        print('사용법: python3 Tools/setup_claude.py --install', file=sys.stderr)
        return 2
    try:
        (install if sys.argv[1] == '--install' else uninstall)(Path.home() / '.claude' / 'settings.json')
    except (ValueError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print('Claude Code 설정을 변경했습니다. Claude Code를 다시 열어 확인하세요.')
    return 0

if __name__ == '__main__': sys.exit(main())
