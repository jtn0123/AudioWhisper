import json
from pathlib import Path
import runpy
import subprocess
import sys
import time

qa = runpy.run_path('scripts/vm/run-desktop-acceptance.py')
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
g = qa['Guest']('/Users/justin/.local/share/audiowhisper-qa/tools/tart.app/Contents/MacOS/tart', 'audiowhisper-qa-tahoe', out)
process = 'first application process whose bundle identifier is "com.audiowhisper.rebuild"'
g.script('tell application "System Events" to tell process "Dock" to click UI element "AudioWhisper" of list 1')
g.wait(lambda s: s['frontmost'] == 'com.audiowhisper.rebuild' and any(w['visible'] and w['bounds']['Width'] >= 800 for w in s['windows']))

def preference_radio(index):
    g.script('tell application "System Events" to keystroke "5" using command down')
    time.sleep(.5)
    g.script(f'tell application "System Events" to tell ({process}) to click radio button {index} of radio group 1 of scroll area 1 of group 1 of window 1')
    time.sleep(.5)

report = {'os': g.run('/usr/bin/sw_vers'), 'binary_sha256': g.run('/usr/bin/shasum', '-a', '256', '/Applications/AudioWhisper.app/Contents/MacOS/AudioWhisper').split()[0], 'captures': []}
for appearance, radio in [('light', 2), ('dark', 3)]:
    preference_radio(radio)
    for index, name in enumerate(['record', 'library', 'models', 'writing', 'preferences'], 1):
        g.script(f'tell application "System Events" to keystroke "{index}" using command down')
        time.sleep(.65)
        if name == 'preferences':
            g.script(f'tell application "System Events" to tell ({process}) to set value of scroll bar 1 of scroll area 1 of group 1 of window 1 to 0.0')
            time.sleep(.25)
        state = g.state()
        w = next(w for w in state['windows'] if w['visible'] and w['bounds']['Width'] >= 800)
        assert w['bounds']['Width'] == 870 and w['bounds']['Height'] == 620, w['bounds']
        assert qa['contained'](state, w['bounds']), 'Workspace escaped screen'
        g.run('/usr/sbin/screencapture', '-x', '-o', '-l', str(w['id']), '/tmp/aw-colors.png')
        data = subprocess.run(g.command + ['/bin/cat', '/tmp/aw-colors.png'], capture_output=True, check=True).stdout
        (out / f'{name}-{appearance}.png').write_bytes(data)
        ax = json.loads(g.run('/Volumes/My Shared Files/qa/inspect-workspace'))
        title = {'record': 'Record', 'library': 'Library', 'models': 'Models & setup', 'writing': 'Writing cleanup', 'preferences': 'Preferences'}[name]
        assert any(row.get('AXDescription') == title and row.get('selected') and row.get('focused') for row in ax), ax
        (out / f'{name}-{appearance}-navigation.json').write_text(json.dumps(ax, indent=2))
        report['captures'].append({'page': name, 'appearance': appearance, 'bounds': w['bounds'], 'contained': True})
        print(f'{name}/{appearance}: captured', flush=True)
preference_radio(1)
g.script('tell application "System Events" to keystroke "1" using command down')
(out / 'capture-report.json').write_text(json.dumps(report, indent=2))
