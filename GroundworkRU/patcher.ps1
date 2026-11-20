param(
    [string]$GameDir = "",
    [switch]$Restore
)
# Русификатор Groundwork Simulator — установщик.
# Русский текст игры хранится внутри game.exe. Скрипт находит этот блок,
# делает резервную копию game.exe и заменяет русские строки новыми.
$ErrorActionPreference = 'Stop'

$code = @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Text.RegularExpressions;

public static class GwRuPatcher
{
    static int IndexOf(byte[] data, byte[] pat, int from)
    {
        int last = data.Length - pat.Length;
        byte first = pat[0];
        for (int i = from; i <= last; i++)
        {
            if (data[i] != first) continue;
            int j = 1;
            while (j < pat.Length && data[i + j] == pat[j]) j++;
            if (j == pat.Length) return i;
        }
        return -1;
    }

    // Минимальный разбор JSON-объекта вида {"строка":"строка",...}
    class Parser
    {
        byte[] d; public int p;
        public Parser(byte[] data, int pos) { d = data; p = pos; }
        void Ws() { while (d[p] == 32 || d[p] == 10 || d[p] == 13 || d[p] == 9) p++; }
        string Str()
        {
            if (d[p] != (byte)'"') throw new Exception("ожидалась строка");
            p++;
            var ms = new MemoryStream();
            var sb = new StringBuilder();
            while (true)
            {
                byte b = d[p];
                if (b == (byte)'"') { p++; break; }
                if (b == (byte)'\\')
                {
                    if (ms.Length > 0) { sb.Append(Encoding.UTF8.GetString(ms.ToArray())); ms.SetLength(0); }
                    char e = (char)d[p + 1]; p += 2;
                    switch (e)
                    {
                        case 'n': sb.Append('\n'); break;
                        case 't': sb.Append('\t'); break;
                        case 'r': sb.Append('\r'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'u': sb.Append((char)Convert.ToInt32(Encoding.ASCII.GetString(d, p, 4), 16)); p += 4; break;
                        default: sb.Append(e); break;
                    }
                    continue;
                }
                ms.WriteByte(b); p++;
            }
            if (ms.Length > 0) sb.Append(Encoding.UTF8.GetString(ms.ToArray()));
            return sb.ToString();
        }
        public List<KeyValuePair<string, string>> Obj()
        {
            var list = new List<KeyValuePair<string, string>>();
            Ws();
            if (d[p] != (byte)'{') throw new Exception("ожидался объект");
            p++; Ws();
            if (d[p] == (byte)'}') { p++; return list; }
            while (true)
            {
                Ws(); string k = Str(); Ws();
                if (d[p] != (byte)':') throw new Exception("ожидалось ':'");
                p++; Ws(); string v = Str(); Ws();
                list.Add(new KeyValuePair<string, string>(k, v));
                if (d[p] == (byte)',') { p++; continue; }
                if (d[p] == (byte)'}') { p++; return list; }
                throw new Exception("ошибка формата JSON");
            }
        }
    }

    public static List<KeyValuePair<string, string>> ParseFile(string path)
    {
        var b = File.ReadAllBytes(path);
        int s = 0;
        if (b.Length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) s = 3;
        return new Parser(b, s).Obj();
    }

    static string Esc(string s)
    {
        var sb = new StringBuilder();
        foreach (char c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.Append("\\u" + ((int)c).ToString("x4"));
                    else sb.Append(c);
                    break;
            }
        }
        return sb.ToString();
    }

    static readonly Regex Ph = new Regex(@"\{[^{}]*\}");

    // Возвращает текст отчёта. Бросает исключение при ошибке.
    public static string Patch(string exePath, string translationPath, string extraPath)
    {
        byte[] data = File.ReadAllBytes(exePath);
        byte[] marker = Encoding.UTF8.GetBytes("\"ARM TOO LOW FOR THE GOLD ROOM \u00b7 USE AN EXCAVATOR\"");
        int found = -1, start = 0, end = 0;
        List<KeyValuePair<string, string>> ruMap = null;
        int pos = 0;
        while (true)
        {
            int i = IndexOf(data, marker, pos);
            if (i < 0) break;
            pos = i + 1;
            int s = i - 1;
            while (s > 0 && (data[s] == 32 || data[s] == 10 || data[s] == 13 || data[s] == 9)) s--;
            if (data[s] != (byte)'{') continue;
            List<KeyValuePair<string, string>> m;
            var pr = new Parser(data, s);
            try { m = pr.Obj(); } catch { continue; }
            foreach (var kv in m)
            {
                if (kv.Key == "LANGUAGE" && kv.Value == "\u042f\u0417\u042b\u041a") // ЯЗЫК
                {
                    found++; start = s; end = pr.p; ruMap = m; break;
                }
            }
            if (ruMap != null) break;
        }
        if (ruMap == null) throw new Exception("Русский блок перевода в game.exe не найден. Возможно, игра обновилась и формат изменился.");

        var tr = new Dictionary<string, string>();
        foreach (var kv in ParseFile(translationPath)) tr[kv.Key] = kv.Value;

        int used = 0, kept = 0, bad = 0;
        var sb = new StringBuilder("{");
        bool firstItem = true;
        foreach (var kv in ruMap)
        {
            string v = kv.Value;
            string t;
            if (tr.TryGetValue(kv.Key, out t))
            {
                // проверка плейсхолдеров: {0}..{n-1}
                int n = Ph.Matches(kv.Key).Count;
                var want = new HashSet<string>();
                for (int k = 0; k < n; k++) want.Add("{" + k + "}");
                var have = new HashSet<string>();
                foreach (Match mm in Ph.Matches(t)) have.Add(mm.Value);
                if (have.IsSubsetOf(want)) { v = t; used++; } else { bad++; }
            }
            else kept++;
            if (!firstItem) sb.Append(',');
            firstItem = false;
            sb.Append('"').Append(Esc(kv.Key)).Append("\":\"").Append(Esc(v)).Append('"');
        }
        // строки, которых нет в каталоге игры (добавляются как новые ключи)
        var have0 = new HashSet<string>();
        foreach (var kv in ruMap) have0.Add(kv.Key);
        int added = 0;
        var extra = File.Exists(extraPath) ? ParseFile(extraPath) : new List<KeyValuePair<string, string>>();
        foreach (var kv in extra)
        {
            if (have0.Contains(kv.Key)) continue;
            sb.Append(",\"").Append(Esc(kv.Key)).Append("\":\"").Append(Esc(kv.Value)).Append('"');
            added++;
        }
        sb.Append('}');
        byte[] blob = Encoding.UTF8.GetBytes(sb.ToString());
        int room = end - start;
        if (blob.Length > room)
            throw new Exception("Новый перевод не помещается в game.exe (" + blob.Length + " > " + room + " байт).");
        byte[] outb = new byte[room];
        Array.Copy(blob, outb, blob.Length - 1);
        for (int k = blob.Length - 1; k < room - 1; k++) outb[k] = 32; // пробелы внутри JSON
        outb[room - 1] = (byte)'}';

        using (var fs = new FileStream(exePath, FileMode.Open, FileAccess.Write))
        {
            fs.Seek(start, SeekOrigin.Begin);
            fs.Write(outb, 0, outb.Length);
        }
        return "Заменено строк: " + used + ", добавлено: " + added + ", оставлено без изменений: " + kept + (bad > 0 ? ", пропущено из-за ошибок: " + bad : "");
    }
}
'@

Add-Type -TypeDefinition $code -Language CSharp

function Find-GameDir {
    param([string]$hint)
    $cands = @()
    if ($hint) { $cands += $hint }
    $cands += $PSScriptRoot
    $cands += (Split-Path $PSScriptRoot -Parent)
    $cands += 'C:\Program Files (x86)\Steam\steamapps\common\Groundwork Simulator'
    foreach ($d in $cands) {
        if ($d -and (Test-Path (Join-Path $d 'game.exe')) -and (Test-Path (Join-Path $d 'assets\locales'))) { return $d }
    }
    # Поиск по библиотекам Steam
    $vdfs = @('C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf', 'C:\Program Files\Steam\steamapps\libraryfolders.vdf')
    foreach ($v in $vdfs) {
        if (Test-Path $v) {
            foreach ($m in [regex]::Matches((Get-Content $v -Raw), '"path"\s+"([^"]+)"')) {
                $p = Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common\Groundwork Simulator'
                if (Test-Path (Join-Path $p 'game.exe')) { return $p }
            }
        }
    }
    return $null
}

Write-Host ''
Write-Host '=== Русификатор Groundwork Simulator ===' -ForegroundColor Yellow
$dir = Find-GameDir $GameDir
if (-not $dir) {
    $dir = Read-Host 'Папка с игрой не найдена. Вставьте путь к папке Groundwork Simulator'
    $dir = $dir.Trim('"')
    if (-not (Test-Path (Join-Path $dir 'game.exe'))) { throw 'В указанной папке нет game.exe' }
}
$exe = Join-Path $dir 'game.exe'
$backup = Join-Path $dir 'game.exe.ru-backup'
Write-Host "Папка игры: $dir"

if (Get-Process -Name 'game' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }) {
    throw 'Игра запущена. Закройте её и запустите установку снова.'
}

if ($Restore) {
    if (-not (Test-Path $backup)) { throw 'Резервная копия game.exe.ru-backup не найдена.' }
    Copy-Item $backup $exe -Force
    Write-Host 'Оригинальный game.exe восстановлен.' -ForegroundColor Green
    return
}

$tr = Join-Path $PSScriptRoot 'ru_translation.json'
if (-not (Test-Path $tr)) { throw 'Файл ru_translation.json не найден рядом со скриптом.' }

# Резервная копия: делаем, если её нет или если game.exe обновился (другой размер/дата)
$needBackup = -not (Test-Path $backup)
if (-not $needBackup) {
    $a = Get-Item $exe; $b = Get-Item $backup
    if ($a.Length -ne $b.Length) { $needBackup = $true }
}
if ($needBackup) {
    Write-Host 'Создаю резервную копию game.exe.ru-backup ...'
    Copy-Item $exe $backup -Force
}

Write-Host 'Устанавливаю перевод (это займёт несколько секунд) ...'
$report = [GwRuPatcher]::Patch($exe, $tr, (Join-Path $PSScriptRoot 'ru_extra.json'))
Write-Host $report
Write-Host 'Готово! Выберите в игре язык «Русский» (Настройки → Общие → Язык).' -ForegroundColor Green
Write-Host 'После обновления игры через Steam запустите установку ещё раз.'
