"""Generate bundled translations; existing user files override these entries.

builtin.json keeps the shared, partial supplement for all languages. zh-cn.json
adds the complete Simplified Chinese interface and reviewed catalogue display text.
"""
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
def lua(value):
    if isinstance(value,dict):
        return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in sorted(value.items()))+'}'
    out=[]
    for byte in value.encode('utf8'):
        ch=chr(byte)
        if ch in '\\"': out.append('\\'+ch)
        elif 32<=byte<127: out.append(ch)
        else: out.append('\\%d'%byte)
    return '"'+''.join(out)+'"'
def build():
    data=json.loads((ROOT/'localization/builtin.json').read_text(encoding='utf8'))
    assert set(data)==set('de es ms fr it jp ko pl pt bp ru cn tc'.split())
    keys=set(data['de'])
    assert all(set(rows)==keys and all(rows.values())for rows in data.values())
    complete=json.loads((ROOT/'localization/zh-cn.json').read_text(encoding='utf8'))
    assert all(isinstance(k,str)and isinstance(v,str)and k and v for k,v in complete.items())
    data['cn'].update(complete)
    return '-- Generated from localization/builtin.json by tools/locale_builtin.py.\nreturn '+lua(data)+'\n'
if __name__=='__main__':
    output=ROOT/'src/editor/locale.lua';body=build()
    if '--check' in sys.argv:
        sys.exit(0 if output.read_text(encoding='utf8')==body else 1)
    output.write_text(body,encoding='utf8')
