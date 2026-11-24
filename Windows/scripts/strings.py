#!/usr/bin/env python3
"""Windows uygulamasının İngilizce metinlerini üretir: Windows/KDDownloadManager/Strings/en.json

Koddaki L.T("…") / L.F("…") anahtarlarını toplar; İngilizcesini önce macOS'un Localizable.xcstrings
dosyasından, yoksa Windows/strings.en.json'dan (yalnızca Windows'a özgü metinler) alır.
Çevirisi olmayan anahtar varsa listeler ve 1 ile çıkar.

    python3 Windows/scripts/strings.py
"""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
app = root / "Windows/KDDownloadManager"
xc = json.loads((root / "Sources/KDDownloadManager/Resources/Localizable.xcstrings").read_text())["strings"]
extra = json.loads((root / "Windows/strings.en.json").read_text())

pattern = re.compile(r'L\.[TF]\(\s*"((?:[^"\\]|\\.)*)"')
keys = set()
for source in app.rglob("*.cs"):
    for match in pattern.finditer(source.read_text()):
        keys.add(json.loads('"' + match.group(1) + '"'))

def plural(variations):
    forms = variations.get("plural", {})
    return {form: forms[form]["stringUnit"]["value"] for form in ("one", "other") if form in forms}


def convert(en):
    """xcstrings → en.json: a string; plural forms {"one", "other"}; or a string with plural
    substitutions {"value", "substitutions": {name: {"arg", "one", "other"}}} (see L.F)."""
    if "variations" in en:
        return plural(en["variations"]) or None
    value = en.get("stringUnit", {}).get("value")
    if value is None or "substitutions" not in en:
        return value
    subs = {name: {"arg": sub.get("argNum", 1), **plural(sub.get("variations", {}))}
            for name, sub in en["substitutions"].items()}
    return {"value": value, "substitutions": subs}


out, missing = {}, []
for key in sorted(keys):
    english = extra.get(key)
    if english is None:
        english = convert(xc.get(key, {}).get("localizations", {}).get("en", {}))
    if english is None:
        missing.append(key)
    else:
        out[key] = english
unused = sorted(set(extra) - keys)
target = app / "Strings/en.json"
target.parent.mkdir(exist_ok=True)
target.write_text(json.dumps(out, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
print(f"{target.relative_to(root)}: {len(out)} metin")
if unused:
    print("Kullanılmayan Windows metinleri:", *unused, sep="\n  ")
if missing:
    print("Çevirisi eksik:", *missing, sep="\n  ")
    sys.exit(1)
