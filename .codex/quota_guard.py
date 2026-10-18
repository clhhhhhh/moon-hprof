"""Cooperative Codex account-quota gate; does not kill the Codex process.

Reads only the current session's token_count telemetry, never credentials.
Exit codes: 0=continue, 50=stop at threshold, 2=unknown (pause and inspect).
Local telemetry is undocumented and may change; it is not a billing API.
"""
import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import sys


def decision(event, threshold, max_age, now):
    timestamp = dt.datetime.fromisoformat(event['timestamp'].replace('Z', '+00:00'))
    age = (now - timestamp).total_seconds()
    if age < -30 or age > max_age:
        raise ValueError('Session quota telemetry is stale or from the future')
    limits = event.get('payload', {}).get('rate_limits') or {}
    windows = {}
    for name in ('primary', 'secondary'):
        window = limits.get(name)
        if window is None:
            continue
        used = window.get('used_percent')
        if isinstance(used, bool) or not isinstance(used, (int, float)):
            raise ValueError('Invalid quota percentage')
        if not math.isfinite(used) or not 0 <= used <= 100:
            raise ValueError('Quota percentage outside 0..100')
        reset = window.get('resets_at')
        if not isinstance(reset, (int, float)) or reset <= now.timestamp():
            raise ValueError('Quota window expired; refresh /status')
        windows[name] = {'used_percent': used, 'resets_at': reset}
    if not windows:
        raise ValueError('No account-quota windows in current session telemetry')
    stop = any(window['used_percent'] >= threshold for window in windows.values())
    return {'action': 'stop' if stop else 'continue', 'threshold_percent': threshold,
            'observed_at': event['timestamp'], 'windows': windows}, 50 if stop else 0


def read_current(session_root, session_id):
    if not session_id or len(session_id) != 36 or any(
            c not in '0123456789abcdef-' for c in session_id.lower()):
        raise ValueError('Pass --session-id or run within the current Codex session')
    files = list(session_root.rglob(f'*{session_id}*.jsonl'))
    if not files:
        raise ValueError('No log found for this session; refusing to use another chat')
    path = max(files, key=lambda p: p.stat().st_mtime)
    with path.open('rb') as stream:
        metadata = json.loads(stream.readline())
        if metadata.get('type') != 'session_meta' or metadata.get('payload', {}).get('id') != session_id:
            raise ValueError('Session metadata does not match the requested chat')
        stream.seek(0, 2)
        start = max(0, stream.tell() - 2 * 1024 * 1024)
        stream.seek(start)
        if start:
            stream.readline()
        tail = stream.read()
    for line in reversed(tail.splitlines()):
        try:
            event = json.loads(line)
        except (ValueError, UnicodeDecodeError):
            continue  # The active writer may have an incomplete final line.
        payload = event.get('payload', {})
        if event.get('type') == 'event_msg' and payload.get('type') == 'token_count':
            return event
    raise ValueError('No recent token_count event; refresh /status')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session-id', default=os.getenv('CODEX_THREAD_ID'))
    parser.add_argument('--threshold', type=float, default=50)
    parser.add_argument('--max-age', type=float, default=300)
    parser.add_argument('--sessions-root', type=Path,
                        default=Path(os.getenv('CODEX_HOME', str(Path.home() / '.codex'))) / 'sessions')
    args = parser.parse_args()
    try:
        if not math.isfinite(args.threshold) or not 0 < args.threshold <= 100:
            raise ValueError('threshold must be in (0,100]')
        if not math.isfinite(args.max_age) or args.max_age <= 0:
            raise ValueError('max-age must be positive')
        result, code = decision(read_current(args.sessions_root, args.session_id),
                                args.threshold, args.max_age, dt.datetime.now(dt.timezone.utc))
    except (ValueError, OSError, KeyError, TypeError) as error:
        result, code = {'action': 'pause_unknown', 'reason': str(error)}, 2
    print(json.dumps(result, ensure_ascii=False))
    return code


if __name__ == '__main__':
    sys.exit(main())
