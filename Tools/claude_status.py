#!/usr/bin/env python3
"""Capture only Claude Code's documented rate-limit status-line fields."""
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import time


def extract(data):
    rate = data.get('rate_limits', {}) if isinstance(data, dict) else {}
    if not isinstance(rate, dict):
        return {}
    out = {}
    for name in ('five_hour', 'seven_day'):
        window = rate.get(name)
        if not isinstance(window, dict):
            continue
        value = window.get('used_percentage')
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 100:
            continue
        item = {'used_percentage': value}
        reset = window.get('resets_at')
        if not isinstance(reset, bool) and isinstance(reset, (int, float)) and math.isfinite(reset) and 0 < reset < 253402300800:
            item['resets_at'] = reset
        out[name] = item
    return out


def save_atomic(directory, name, value):
    fd, temp = tempfile.mkstemp(prefix='.status-', dir=directory)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            json.dump(value, file, separators=(',', ':'), allow_nan=False)
        os.replace(temp, directory / name)
    finally:
        if os.path.exists(temp): os.unlink(temp)


def main():
    try:
        data = json.loads(sys.stdin.read(1_000_001))
        limits = extract(data)
        directory = Path.home() / 'Library' / 'Application Support' / 'UsageEdge' / 'ClaudeStatus'
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(directory, 0o700)
        now = time.time()
        diagnostic = {'checked_at': now, 'rate_limits_present': isinstance(data, dict) and isinstance(data.get('rate_limits'), dict), 'valid_window_count': len(limits)}
        diagnostic_path = directory / 'diagnostic.json'
        try:
            old = json.loads(diagnostic_path.read_text(encoding='utf-8'))
            unchanged = (old.get('rate_limits_present') == diagnostic['rate_limits_present'] and old.get('valid_window_count') == diagnostic['valid_window_count'] and 0 <= now - old.get('checked_at', 0) < 30)
        except (OSError, ValueError, TypeError, AttributeError):
            unchanged = False
        if not unchanged:
            save_atomic(directory, 'diagnostic.json', diagnostic)
        if limits:
            save_atomic(directory, 'snapshot.json', {'captured_at': now, 'rate_limits': limits})
    except (OSError, ValueError, TypeError):
        pass
    print('Claude')

if __name__ == '__main__': main()
