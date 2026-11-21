# Генерирует дополнительные ключи для ru_extra.json:
# 1) варианты строк после игровых переименований (cleanup table -> Gold Table и т.п.)
# 2) отдельные абзацы многоабзацных подсказок (игра показывает их по отдельности)
import json, re, os, sys
sys.stdout.reconfigure(encoding='utf-8')
here = os.path.dirname(os.path.abspath(__file__))
en = list(json.load(open(os.path.join(here, 'en.embedded.json'), encoding='utf-8')))
rel = os.path.join(here, '..', 'GroundworkRU')
ru = json.load(open(os.path.join(rel, 'ru_translation.json'), encoding='utf-8'))
manual = json.load(open(os.path.join(here, 'extra_manual.json'), encoding='utf-8'))

# (английский было, английский стало, [(русский было, русский стало), ...])
REN = [
    ('open Store', 'open Machine Dealer', [('"Магазин"', '"Дилер техники"')]),
    ('choose Sell Filed Gold', 'select CHOOSE GOLD TO SELL', [('выберите "Продать оприходованное золото"', 'выберите "СКОЛЬКО ЗОЛОТА ПРОДАТЬ"')]),
    ('Sell Filed Gold', 'CHOOSE GOLD TO SELL', []),
    ('Metal detector', 'Material detector', []),
    ('metal detector', 'material detector', []),
    ('Hand scanner', 'Material detector', [('Ручной сканер', 'Металлоискатель')]),
    ('hand scanner', 'material detector', [('ручной сканер', 'металлоискатель'), ('ручного сканера', 'металлоискателя')]),
    ('Gold table + tent', 'Gold Table', []),
    ('gold table + tent', 'Gold Table', []),
    ('Gold wash table', 'Gold Table', []),
    ('gold wash table', 'Gold Table', []),
    ('Cleanup table', 'Gold Table', [('Стол доводки', 'Золотой стол')]),
    ('cleanup table', 'Gold Table', [('Стол доводки', 'Золотой стол'), ('столе доводки', 'золотом столе')]),
    ('Gold table', 'Gold Table', []),
    ('gold table', 'Gold Table', []),
    ('Bucket pallet', 'Mat pallet', [('Поддон с вёдрами', 'Поддон с матами')]),
    ('bucket pallet', 'mat pallet', [('поддон с вёдрами', 'поддон с матами'), ('Поддон с вёдрами', 'Поддон с матами')]),
    ('Cleanup pallet', 'Mat pallet', [('Поддон для доводки', 'Поддон с матами')]),
    ('cleanup pallet', 'mat pallet', [('поддон для доводки', 'поддон с матами')]),
    ('Washplant', 'Trommel', [('Промывочная установка', 'Тромель')]),
    ('washplant', 'trommel', [('промывочную установку', 'тромель'), ('промывочная установка', 'тромель')]),
    ('Wash plant', 'Trommel', []),
    ('wash plant', 'trommel', []),
    ('The old pickup', 'The Old truck', [('Старый пикап', 'Старый грузовик')]),
    ('the old pickup', 'the Old truck', [('старого пикапа', 'старого грузовика'), ('старый пикап', 'старый грузовик')]),
    ('The pickup', 'The Old truck', []),
    ('the pickup', 'the Old truck', []),
    ('Carry the pallet to the table', 'Carry the mat pallet to the Gold Table', [('Отнесите поддон к столу', 'Отнесите поддон с матами к золотому столу')]),
]

def apply(e, r):
    for a, b, rr in REN:
        if a in e:
            e = e.replace(a, b)
            for x, y in rr:
                r = r.replace(x, y)
    return e, r

keys = set(en)
extra = {}
def add(e, r):
    if e in keys or e in extra or not e.strip():
        return
    extra[e] = r

pairs = [(k, ru[k]) for k in en]
for e, r in pairs:
    variants = [(e, r)]
    ev, rv = apply(e, r)
    if ev != e:
        variants.append((ev, rv))
        add(ev, rv)
    for ve, vr in variants:
        if '\n\n' in ve:
            ep = ve.split('\n\n'); rp = vr.split('\n\n')
            if len(ep) == len(rp):
                for a, b in zip(ep, rp):
                    if '{' in a and not re.search(r'\{\d+\}', b) and re.search(r'\{[^}]*\}', a):
                        pass
                    # абзацы с плейсхолдерами пропускаем: нумерация там своя
                    if re.search(r'\{[^}]*\}', a):
                        continue
                    add(a, b)
for k, v in manual.items():
    extra.setdefault(k, v)
json.dump(extra, open(os.path.join(rel, 'ru_extra.json'), 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=1)
full = dict(ru); full.update(extra)
size = len(json.dumps(full, ensure_ascii=False, separators=(',', ':')).encode('utf-8'))
print('extra keys', len(extra), 'total size', size, 'budget 557863 free', 557863 - size)
