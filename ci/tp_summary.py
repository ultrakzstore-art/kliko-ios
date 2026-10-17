"""Сводка Time Profiler (xctrace export, таблица time-profile) — разбор зависаний и тормозов в CI (job perf).

Читает XML экспорта, раскрывает ссылки ref на кадры и стеки, считает для главного потока: «своё» время (верхний кадр)
и «включённое» (кадр где-либо в стеке), отдельно кадры из Kliko. Печатает топы — их читают в журнале прогона.
"""
import sys
import xml.etree.ElementTree as ET
from collections import Counter

def main(path, limit=40):
    root = ET.parse(path).getroot()
    by_id = {}
    for el in root.iter():
        i = el.get('id')
        if i is not None:
            by_id[i] = el

    def resolve(el):
        r = el.get('ref')
        return by_id.get(r, el) if r is not None else el

    def frames(bt):
        bt = resolve(bt)
        names = []
        for fr in bt.findall('frame'):
            fr = resolve(fr)
            name = fr.get('name') or '?'
            binary = fr.find('binary')
            bname = resolve(binary).get('name') if binary is not None else ''
            names.append((name, bname or ''))
        return names

    own = Counter(); incl = Counter(); own_k = Counter(); incl_k = Counter()
    total = 0
    for row in root.iter('row'):
        th = row.find('thread')
        if th is None:
            continue
        th = resolve(th)
        fmt = th.get('fmt') or ''
        if 'Main Thread' not in fmt:
            continue
        w = row.find('weight')
        weight = 1
        if w is not None:
            w = resolve(w)
            try:
                weight = int(w.text or '1')
            except ValueError:
                weight = 1
        bt = row.find('backtrace')
        if bt is None:
            continue
        fs = frames(bt)
        if not fs:
            continue
        total += weight
        own[fs[0][0]] += weight
        seen = set()
        for name, b in fs:
            if name in seen:
                continue
            seen.add(name)
            incl[name] += weight
            if b == 'Kliko' or b.startswith('Kliko.'):
                incl_k[name] += weight
        for name, b in fs:
            if b == 'Kliko' or b.startswith('Kliko.'):
                own_k[name] += weight
                break
    ms = lambda v: '%.0f ms' % (v / 1e6) if total > 10**6 else str(v)
    print('Главный поток: всего %s' % ms(total))
    print('\n== Своё время (верхний кадр), топ %d' % limit)
    for n, v in own.most_common(limit):
        print('%10s  %s' % (ms(v), n[:180]))
    print('\n== Ближайший кадр Kliko (кто вызвал), топ %d' % limit)
    for n, v in own_k.most_common(limit):
        print('%10s  %s' % (ms(v), n[:180]))
    print('\n== Включённое время, кадры Kliko, топ %d' % limit)
    for n, v in incl_k.most_common(limit):
        print('%10s  %s' % (ms(v), n[:180]))

if __name__ == '__main__':
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 40)
