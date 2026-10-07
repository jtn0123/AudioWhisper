import json
from pathlib import Path
import runpy
import time
import wave

q = runpy.run_path('scripts/vm/run-desktop-acceptance.py')
out = Path('/Users/justin/.local/share/audiowhisper-qa/pr-regrade-2026-10-07')
g = q['Guest']('/Users/justin/.local/share/audiowhisper-qa/tools/tart.app/Contents/MacOS/tart',
               'audiowhisper-qa-tahoe', out)
store = '/Users/admin/Library/Application Support/AudioWhisper Rebuild/history.store'
def query(sql):
    return g.run('/usr/bin/sqlite3', '-readonly', store, sql)

report = {'case': 'file-import-duration', 'vm': 'audiowhisper-qa-tahoe'}
before = int(query('SELECT MAX(Z_PK) FROM ZTRANSCRIPTIONRECORD;'))
report['previous_record_id'] = before
with wave.open('Tests/Resources/speech_sample.wav') as w:
    report['fixture_duration_seconds'] = w.getnframes() / w.getframerate()
rows = json.loads(g.run('/Volumes/My Shared Files/qa/colors-tools/inspect-buttons'))
button = next(r for r in rows if r.get('AXDescription') == 'Transcribe a file…' and r['enabled'])
x, y = button['position']; width, height = button['size']
g.run('/Volumes/My Shared Files/qa/input', 'click', str(x + width/2), str(y + height/2))
time.sleep(.5)
g.key(5, 'command down, shift down')
time.sleep(.5)
g.script('tell application "System Events" to keystroke "/Volumes/My Shared Files/qa/speech_sample.wav"')
g.key(36, '')
time.sleep(1)
g.key(36, '')
deadline = time.monotonic() + 60
while time.monotonic() < deadline:
    last = int(query('SELECT MAX(Z_PK) FROM ZTRANSCRIPTIONRECORD;'))
    if last > before:
        break
    time.sleep(.3)
else:
    g.capture('import-duration-blocked')
    raise RuntimeError('No new imported transcript within 60 seconds')
report['new_record'] = json.loads(query('SELECT json_object(\'id\',Z_PK,\'duration\',ZDURATION,\'text\',ZTEXT) FROM ZTRANSCRIPTIONRECORD ORDER BY Z_PK DESC LIMIT 1;'))
report['result'] = 'reproduced' if report['new_record']['duration'] is None else 'not-reproduced'
g.capture('import-duration-result')
(out/'import-duration.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
