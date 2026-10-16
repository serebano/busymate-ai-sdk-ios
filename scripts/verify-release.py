from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
m=json.loads((root/'release-manifest.json').read_text())
for name,expected in m['files'].items():
    actual=hashlib.sha256((root/name).read_bytes()).hexdigest()
    assert actual==expected, f"Frozen source changed: {name}"
    print(f"verified {name} {actual}")
assert m['version']=='1.0.2'

# Every release attaches each adapter source file under its basename, listed in SHA256SUMS.
assets=m.get('adapterAssets') or []
assert assets, 'release-manifest.json must declare adapterAssets'
names=[Path(a).name for a in assets]
assert len(set(names))==len(names), 'adapter asset basenames must be unique'
for a in assets:
    assert a in m['files'], f'adapter asset {a} is not pinned in files'
    actual=hashlib.sha256((root/a).read_bytes()).hexdigest()
    assert actual==m['files'][a], f'adapter asset changed: {a}'
    print(f"verified adapter asset {Path(a).name} {actual}")

# Build success on a newer Xcode alone cannot detect an incompatible saved project format.
import re
project=(root/'example-app/BusymateSDKExample.xcodeproj/project.pbxproj').read_text()
version=re.search(r'objectVersion = (\d+);',project)
assert version and int(version.group(1))==60, 'Expected Xcode 15 project format (objectVersion 60)'
assert 'projectFormat: xcode15_0' in (root/'example-app/project.yml').read_text()
assert 'PBXFileSystemSynchronizedRootGroup' not in project
print('verified example Xcode 15 project format (objectVersion 60)')
