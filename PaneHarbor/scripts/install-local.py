#!/usr/bin/env python3
"""Install the locally verified bundle with an atomic, recoverable app backup."""
from pathlib import Path
import argparse, datetime, hashlib, json, plistlib, re, subprocess
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--destination', default='/Applications/PaneHarbor.app', help='Local app bundle destination; use PaneHarbor Preview.app for the local beta.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = root/'build/PaneHarbor.app'
installed = Path(args.destination)
assert installed.parent == Path('/Applications') and installed.name in ('PaneHarbor.app', 'PaneHarbor Preview.app'), 'Only the owned application destinations are supported.'
assert source.is_dir(), 'Build the app first.'
assert subprocess.run(['pgrep','-f','^'+re.escape(str(installed/'Contents/MacOS/PaneHarbor'))+'$'], capture_output=True).returncode != 0, 'Quit PaneHarbor before replacing its bundle.'
subprocess.run(['codesign','--verify','--deep','--strict',str(source)],check=True)
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = root/'build/backups'/('installed-before-'+stamp)
backup.mkdir(parents=True)
staged = Path('/Applications/PaneHarbor.installing.app')
assert not staged.exists(), 'An incomplete staging bundle exists; inspect it before retrying.'
subprocess.run(['ditto',str(source),str(staged)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(staged)],check=True)
def manifest(folder):
    return {str(f.relative_to(folder)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(folder.rglob('*')) if f.is_file()}
assert manifest(source) == manifest(staged)
lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if installed.exists():
    subprocess.run([lsregister,'-u',str(installed)],check=True)
    saved = backup/'PaneHarbor.saved-bundle'
    installed.rename(saved)
    # LaunchServices discovers APPL bundles even without an .app suffix.
    # Preserve the signed plist bytes under a non-discoverable name.
    (saved/'Contents/Info.plist').rename(saved/'Contents/Info.restore-plist')
staged.rename(installed)
subprocess.run(['codesign','--verify','--deep','--strict',str(installed)],check=True)
assert manifest(source) == manifest(installed)
receipt = {'bundleID':plistlib.loads((installed/'Contents/Info.plist').read_bytes())['CFBundleIdentifier'],
    'installed':str(installed),'backup':str(backup),'binarySHA256':hashlib.sha256((installed/'Contents/MacOS/PaneHarbor').read_bytes()).hexdigest(),
    'manifest':manifest(installed),'scope':'Application bundle replacement only. Existing sandbox data is retained; not modified or migrated.',
    'timestamp':datetime.datetime.now().isoformat(),
    'restoreInstructions':'Quit the app. Rename saved-bundle/Contents/Info.restore-plist to Info.plist, then copy the saved bundle to the installed .app path. Verify its signature before launch.'}
(backup/'installation.json').write_text(json.dumps(receipt,indent=2))
subprocess.run([lsregister,'-f',str(installed)],check=True)
print(json.dumps({k:v for k,v in receipt.items() if k!='manifest'},indent=2))
