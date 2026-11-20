#!/usr/bin/env python3
"""Check shared bilingual UI copy and format arguments without launching devices."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / 'App/Resources/Localizable.xcstrings').read_text())['strings']
formats = re.compile(r'%(?:\d+\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(ld|lld|@)')
for key, item in catalog.items():
    zh = item['localizations']['zh-Hans']['stringUnit']['value']
    en = item['localizations']['en']['stringUnit']['value']
    assert zh and en, key
    assert not re.search(r'[\u4e00-\u9fff]', en), key
    assert formats.findall(key) == formats.findall(zh), (key, zh)
    assert formats.findall(key) == formats.findall(en), (key, en)

for path in list((root / 'App').rglob('*.swift')) + list((root / 'Sources/EnchantCore').glob('*.swift')):
    if 'Tests' in str(path):
        continue
    source = path.read_text()
    for key in re.findall(r'L10n\.(?:text|format)\("((?:[^"\\]|\\.)*)"', source):
        assert key in catalog, (path.relative_to(root), key)
    # Includes constants passed through String properties, validation errors and AX labels.
    for key in re.findall(r'"((?:[^"\\]|\\.)*)"', source):
        if re.search(r'[\u4e00-\u9fff]', key) and '\\(' not in key:
            assert key in catalog, (path.relative_to(root), key)

purposes = json.loads((root / 'App/Resources/InfoPlist.xcstrings').read_text())['strings']
assert set(purposes) == {'NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription', 'NSMotionUsageDescription'}
for key, item in purposes.items():
    for language in ['zh-Hans', 'en']:
        assert item['localizations'][language]['stringUnit']['value'], (key, language)
print(f'PASS {len(catalog)} bilingual entries, native display coverage, format arguments and permission copy')
