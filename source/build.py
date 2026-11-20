# Сборка ru.json из файлов перевода work/tr/*.txt
# Формат строки: <id>\t<перевод с JSON-экранированием (\n, \", \\)>
# Плейсхолдеры можно писать как в английском ({control0}, {}, {:.1}) - скрипт
# сам переведёт их в позиционные {0},{1}... по порядку в английском ключе.
# Можно писать и сразу {0},{1} (для перестановки).
import json, re, glob, os, sys
sys.stdout.reconfigure(encoding='utf-8')
here = os.path.dirname(os.path.abspath(__file__))
en = json.load(open(os.path.join(here, 'en.embedded.json'), encoding='utf-8'))
orig = json.load(open(os.path.join(here, 'ru.embedded.json'), encoding='utf-8'))
keys = list(en)
PH = re.compile(r'\{[^{}]*\}')

tr = {}
for f in sorted(glob.glob(os.path.join(here, 'tr', '*.txt'))):
    for ln, line in enumerate(open(f, encoding='utf-8').read().split('\n'), 1):
        if not line.strip() or line.startswith('#'):
            continue
        i, _, t = line.partition('\t')
        try:
            i = int(i)
            t = json.loads('"' + re.sub(r'(?<!\\)"', r'\\"', t) + '"')
        except Exception as e:
            print('PARSE', f, ln, repr(line[:80]), e); continue
        tr[i] = t
        if re.search('[—–«»]', t): print('TYPO', i, t[:60])

def positional(key, t):
    kp = PH.findall(key)
    tp = PH.findall(t)
    if all(re.fullmatch(r'\{\d+\}', p) for p in tp) and tp:
        return t
    # сопоставляем по порядку вхождения одинаковых токенов
    slots = {}
    for idx, p in enumerate(kp):
        slots.setdefault(p, []).append(idx)
    used = {}
    def rep(m):
        p = m.group(0)
        if re.fullmatch(r'\{\d+\}', p) and p not in slots:
            return p
        lst = slots.get(p)
        if not lst:
            raise ValueError('unknown placeholder %s' % p)
        n = used.get(p, 0); used[p] = n + 1
        if n >= len(lst):
            raise ValueError('too many %s' % p)
        return '{%d}' % lst[n]
    return PH.sub(rep, t)

out = {}
errors = 0
missing = []
for i, k in enumerate(keys):
    if i in tr:
        try:
            v = positional(k, tr[i])
        except ValueError as e:
            print('PH', i, repr(k), '=>', repr(tr[i]), e); errors += 1
            v = orig[k]
        want = set('{%d}' % n for n in range(len(PH.findall(k))))
        if not set(PH.findall(v)) <= want:
            print('MISMATCH', i, repr(k), '=>', repr(v)); errors += 1
            v = orig[k]
        # пробелы/переводы строк по краям должны совпадать
        lead = re.match(r'^\s*', k).group(0); trail = re.search(r'\s*$', k).group(0)
        v = lead + v.strip() + trail
        out[k] = v
    else:
        missing.append(i)
        out[k] = orig[k]
print('translated', len(tr), 'of', len(keys), 'missing', len(missing), 'errors', errors)
if missing:
    print('first missing ids:', missing[:20])
rel = os.path.join(here, '..', 'GroundworkRU')
os.makedirs(rel, exist_ok=True)
json.dump(out, open(os.path.join(rel, 'ru_translation.json'), 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=1)
size = len(json.dumps(out, ensure_ascii=False, separators=(',', ':')).encode('utf-8'))
print('minified size', size, 'budget 557863', 'free', 557863 - size)
