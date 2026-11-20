#!/usr/bin/env python3
"""Build one offline HTML from reviewed templates, original art and licensed fonts."""
from pathlib import Path
import base64,json,re
root=Path(__file__).resolve().parent.parent
assets=root/'assets'
def data(path,mime): return 'data:'+mime+';base64,'+base64.b64encode(path.read_bytes()).decode()
fonts=[('Fusion','FusionPixel-12px-Proportional-zh_hans.ttf',400),('Silk','Silkscreen-Regular.ttf',400),('Silk','Silkscreen-Bold.ttf',700)]
faces=''.join('@font-face{font-family:'+family+';font-weight:'+str(weight)+';src:url('+data(assets/'fonts'/file,'font/ttf')+')} ' for family,file,weight in fonts)
template=(assets/'source/preview-template.html').read_text()
icons={p.stem:p.read_text().strip() for p in sorted((assets/'icons').glob('*.svg'))}
template=template.replace('__ICONS__',json.dumps(icons))
catalog=json.loads((root/'App/Resources/Localizable.xcstrings').read_text())
copy={key:{lang:entry['localizations'][lang]['stringUnit']['value'] for lang in ['zh-Hans','en']} for key,entry in catalog['strings'].items() if all(lang in entry.get('localizations',{}) for lang in ['zh-Hans','en'])}
template=template.replace('__COPY__',json.dumps(copy,ensure_ascii=False))
images={name:data(assets/'images'/('enhanced-sword.png' if name=='enchanted-sword' else 'enhanced-app-icon.png' if name=='app-icon' else name+'.png'),'image/png') for name in ['app-icon','enchanted-sword','plain-sword','magic-journal']}
for name,url in images.items(): template=template.replace('images/'+name+'.png',url)
dynamic={name:url for name,url in images.items() if name!='app-icon'}
dynamic['sword-tab']=data(root/'App/Resources/Assets.xcassets/SwordIcon.imageset/enhanced-sword.png','image/png')
dynamic['journal-tab']=data(root/'App/Resources/Assets.xcassets/JournalIcon.imageset/magic-journal.png','image/png')
template=template.replace('const asset=name=>','const imageAssets='+json.dumps(dynamic)+';\nconst asset=name=>').replace('src="images/${name}.png"','src="${imageAssets[name]}"')
html='<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Enchant · 界面与场景</title><style>'+faces+(assets/'source/preview.css').read_text()+template
(assets/'preview.html').write_text(html)
print('Built assets/preview.html with embedded artwork and fonts')
