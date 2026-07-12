#!/usr/bin/env python3
"""
fructa lang dedupe
Run from repo root:  python3 tools/lang_dedupe.py            (report only)
                     python3 tools/lang_dedupe.py --write     (rewrite the file)

JSON permits duplicate keys and the LAST one wins at parse time. So any earlier
definition of a repeated key is dead copy: edit it and the app ignores you.

This keeps the last occurrence of every key, which is exactly what the app is
already rendering. Deduping is therefore a no-op at runtime, and it makes the
file honest about what is actually in use.

Also reports duplicate VALUES across distinct keys. Those are consolidation
candidates, not bugs, and are never touched automatically: two keys with the
same English word can diverge in another language.
"""
import io
import json
import os
import sys
from collections import OrderedDict, defaultdict

LANG = os.path.join(os.getcwd(), 'assets', 'lang')

# namespace print order; anything unlisted is appended alphabetically
ORDER = ['app', 'nav', 'common', 'category', 'fundType', 'markets', 'company',
         'compare', 'portfolio', 'alerts', 'stocks', 'insure', 'learn', 'lesson',
         'blog', 'backup', 'update', 'onboarding', 'settings']


def pairs_hook(pairs):
    """Keep every pair, including repeats, so we can see the duplicates."""
    return pairs


def dump(d):
    groups = OrderedDict((g, []) for g in ORDER)
    for k in d:
        groups.setdefault(k.split('.')[0], []).append(k)
    lines = []
    for _, keys in groups.items():
        if not keys:
            continue
        for k in sorted(keys):
            lines.append('  %s: %s' % (json.dumps(k),
                                       json.dumps(d[k], ensure_ascii=False)))
        lines.append('')
    while lines and lines[-1] == '':
        lines.pop()
    live = [i for i, l in enumerate(lines) if l]
    for i in live[:-1]:
        lines[i] += ','
    return '{\n' + '\n'.join(lines) + '\n}\n'


def run(path, write):
    raw = io.open(path, encoding='utf-8').read()
    try:
        pairs = json.loads(raw, object_pairs_hook=pairs_hook)
    except json.JSONDecodeError as e:
        print('INVALID JSON: %s -> %s' % (path, e))
        return 1

    seen = defaultdict(list)
    for k, v in pairs:
        seen[k].append(v)
    dupes = {k: vs for k, vs in seen.items() if len(vs) > 1}

    conflicts = {k: vs for k, vs in dupes.items() if len(set(vs)) > 1}
    identical = sorted(k for k in dupes if k not in conflicts)

    print('=== %s' % os.path.basename(path))
    print('pairs in file : %d' % len(pairs))
    print('unique keys   : %d' % len(seen))
    print('duplicate keys: %d  (%d identical, %d CONFLICTING)'
          % (len(dupes), len(identical), len(conflicts)))

    if conflicts:
        print('\n-- conflicting duplicates (the LAST value is what ships) --')
        for k in sorted(conflicts):
            vs = conflicts[k]
            print('  %s' % k)
            for i, v in enumerate(vs):
                tag = 'LIVE ' if i == len(vs) - 1 else 'dead '
                print('    %s %s' % (tag, v[:88]))

    if identical:
        print('\n-- identical duplicates (safe to drop) --')
        for k in identical:
            print('  %s' % k)

    # last-wins, which is what the parser already does
    final = OrderedDict()
    for k, v in pairs:
        final[k] = v

    v2k = defaultdict(list)
    for k, v in final.items():
        if isinstance(v, str):
            v2k[v.strip().lower()].append(k)
    same_value = {v: ks for v, ks in v2k.items() if len(ks) > 1}
    if same_value:
        print('\n-- distinct keys sharing one value (review, not auto-fixed) --')
        for v, ks in sorted(same_value.items()):
            print('  %-38s %s' % (repr(v[:36]), ', '.join(sorted(ks))))

    if write:
        io.open(path, 'w', encoding='utf-8').write(dump(final))
        check = json.loads(io.open(path, encoding='utf-8').read())
        assert len(check) == len(final)
        print('\nrewrote %s: %d pairs -> %d keys, no value changed'
              % (os.path.basename(path), len(pairs), len(final)))
    else:
        print('\n(report only. re-run with --write to rewrite the file)')
    return 0


def main():
    write = '--write' in sys.argv
    if not os.path.isdir(LANG):
        sys.exit('run me from the repo root (no ./assets/lang)')
    rc = 0
    for f in sorted(os.listdir(LANG)):
        if f.endswith('.json'):
            rc |= run(os.path.join(LANG, f), write)
            print()
    sys.exit(rc)


if __name__ == '__main__':
    main()
