#!/usr/bin/env python3
"""Check complete language coverage, format arguments and generated resources."""
import argparse
import collections
import json
import re
from pathlib import Path
from sync_localizations import ROOT, CATALOG, sync

PLACEHOLDER = re.compile(r'%(?:(\d+)\$)?(?:[-+0 #]*\d*(?:\.\d+)?)?(lld|ld|d|@|f)')

def placeholders(value):
    return collections.Counter(kind for _, kind in PLACEHOLDER.findall(value))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stringsdata-root', type=Path)
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text())
    strings = catalog['strings']
    supported_source = (ROOT / 'Packages/FileMailerCore/Sources/FileMailerDomain/FileMailerLocalization.swift').read_text()
    identifiers_block = supported_source.split('supportedIdentifiers = [', 1)[1].split(']', 1)[0]
    locales = re.findall(r'"([^"]+)"', identifiers_block)
    failures = []
    for key, item in strings.items():
        loc = item.get('localizations', {})
        english = loc.get('en', {}).get('stringUnit', {}).get('value', '')
        for locale in locales:
            unit = loc.get(locale, {}).get('stringUnit', {})
            value = unit.get('value')
            if value is None or (key and not value):
                failures.append(f'Missing {locale}: {key}')
                continue
            if unit.get('state') != 'translated':
                failures.append(f'Untranslated state {locale}: {key}')
            if placeholders(value) != placeholders(key):
                failures.append(f'Format arguments differ {locale}: {key}')
            if re.search(r'98765\d|\[PH\s*\d+\]', value):
                failures.append(f'Translation marker {locale}: {key}')
            if (not locale.startswith(('en', 'fr')) and value == english and english != key
                    and len(re.findall(r'\w+', english)) > 1):
                failures.append(f'English copied into {locale}: {key}')
    for source in [*(ROOT / 'App').rglob('*.swift'), *(ROOT / 'Packages/FileMailerCore/Sources').rglob('*.swift')]:
        for match in re.finditer(r'(?:localizedString|\.string|\.format)\(\s*"((?:[^"\\]|\\.)*)"', source.read_text()):
            key = match[1]
            if '\\(' in key or not key: continue
            try: key = json.loads('"' + key + '"')
            except json.JSONDecodeError: continue
            if key not in strings:
                failures.append(f'Uncatalogued key in {source.relative_to(ROOT)}: {key}')
    if args.stringsdata_root:
        for source in args.stringsdata_root.rglob('*.stringsdata'):
            data = json.loads(source.read_text())
            if '/App/' not in data.get('source', ''): continue
            for item in data.get('tables', {}).get('Localizable', []):
                key = item['key']
                if key and key not in strings and re.search(r'\w{2}', key):
                    failures.append(f'Uncatalogued compiled UI string: {key}')
    if failures:
        raise SystemExit('\n'.join(sorted(set(failures))))
    sync(check=True)
    print(f'PASS: {len(strings)} strings, {len(locales)} languages, no missing translations or English copies')

if __name__ == '__main__':
    main()
