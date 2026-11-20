# Достаёт английский и русский каталоги строк из вашего game.exe
# в en.embedded.json и ru.embedded.json (нужны для build.py).
# Запуск: python extract_catalogs.py "путь\к\game.exe"
import json, sys, os
sys.stdout.reconfigure(encoding="utf-8")
exe = sys.argv[1] if len(sys.argv) > 1 else 'game.exe'
data = open(exe, 'rb').read()
marker = '"ARM TOO LOW FOR THE GOLD ROOM \u00b7 USE AN EXCAVATOR"'.encode('utf-8')
here = os.path.dirname(os.path.abspath(__file__))
found = {}
pos = 0
dec = json.JSONDecoder()
while True:
    i = data.find(marker, pos)
    if i < 0:
        break
    pos = i + 1
    s = i - 1
    while data[s] in b' \r\n\t':
        s -= 1
    if data[s:s + 1] != b'{':
        continue
    text = data[s:s + 2_000_000].decode('utf-8', 'ignore')
    try:
        obj, end = dec.raw_decode(text)
    except ValueError:
        continue
    lang = obj.get('LANGUAGE')
    if lang == 'LANGUAGE':
        found['en'] = obj
    elif lang == '\u042f\u0417\u042b\u041a':  # ЯЗЫК
        found['ru'] = obj
for k in ('en', 'ru'):
    if k not in found:
        sys.exit('Каталог %s не найден' % k)
    json.dump(found[k], open(os.path.join(here, k + '.embedded.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('ok: en %d строк, ru %d строк' % (len(found['en']), len(found['ru'])))
