import copy
import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import quota_guard


class QuotaGuardTests(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 10, 18, 9, 0, tzinfo=dt.timezone.utc)
        self.event = {'type': 'event_msg', 'timestamp': self.now.isoformat(),
                      'payload': {'type': 'token_count', 'rate_limits': {
                          'primary': {'used_percent': 12, 'resets_at': self.now.timestamp() + 600},
                          'secondary': {'used_percent': 49, 'resets_at': self.now.timestamp() + 3600}}}}

    def decide(self, event=None):
        return quota_guard.decision(event or self.event, 50, 300, self.now)

    def test_below_threshold_continues(self):
        result, code = self.decide()
        self.assertEqual((result['action'], code), ('continue', 0))

    def test_exactly_fifty_and_either_window_stop(self):
        for name in ('primary', 'secondary'):
            for percent in (50, 75, 100):
                event = copy.deepcopy(self.event)
                event['payload']['rate_limits'][name]['used_percent'] = percent
                result, code = self.decide(event)
                self.assertEqual((result['action'], code), ('stop', 50))

    def test_invalid_or_missing_quota_is_unknown(self):
        for invalid in (None, True, '50', -1, 101, float('nan'), float('inf')):
            event = copy.deepcopy(self.event)
            event['payload']['rate_limits']['primary']['used_percent'] = invalid
            with self.assertRaises(ValueError):
                self.decide(event)
        event = copy.deepcopy(self.event)
        event['payload']['rate_limits'] = None
        with self.assertRaises(ValueError):
            self.decide(event)

    def test_stale_future_and_expired_window_are_unknown(self):
        for seconds in (-301, 31):
            event = copy.deepcopy(self.event)
            event['timestamp'] = (self.now + dt.timedelta(seconds=seconds)).isoformat()
            with self.assertRaises(ValueError):
                self.decide(event)
        event = copy.deepcopy(self.event)
        event['payload']['rate_limits']['primary']['resets_at'] = self.now.timestamp()
        with self.assertRaises(ValueError):
            self.decide(event)

    def test_matches_session_and_tolerates_incomplete_final_line(self):
        session_id = '00000000-0000-0000-0000-000000000001'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / f'rollout-{session_id}.jsonl'
            meta = {'type': 'session_meta', 'payload': {'id': session_id}}
            path.write_text(json.dumps(meta) + '\n' + json.dumps(self.event) + '\n{"partial":', encoding='utf-8')
            self.assertEqual(quota_guard.read_current(Path(directory), session_id), self.event)
            meta['payload']['id'] = 'another-chat'
            path.write_text(json.dumps(meta) + '\n' + json.dumps(self.event), encoding='utf-8')
            with self.assertRaises(ValueError):
                quota_guard.read_current(Path(directory), session_id)

    def test_stop_exit_code_is_available_to_a_caller(self):
        session_id = '00000000-0000-0000-0000-000000000001'
        with tempfile.TemporaryDirectory() as directory:
            event = copy.deepcopy(self.event)
            event['timestamp'] = dt.datetime.now(dt.timezone.utc).isoformat()
            for window in event['payload']['rate_limits'].values():
                window['resets_at'] = dt.datetime.now(dt.timezone.utc).timestamp() + 600
            event['payload']['rate_limits']['primary']['used_percent'] = 50
            meta = {'type': 'session_meta', 'payload': {'id': session_id}}
            path = Path(directory) / f'rollout-{session_id}.jsonl'
            path.write_text(json.dumps(meta) + '\n' + json.dumps(event), encoding='utf-8')
            process = subprocess.run([sys.executable, '-B', str(Path(quota_guard.__file__)),
                                      '--session-id', session_id, '--sessions-root', directory],
                                     capture_output=True, text=True, check=False)
            self.assertEqual(process.returncode, 50)
            self.assertEqual(json.loads(process.stdout)['action'], 'stop')


if __name__ == '__main__':
    unittest.main()
