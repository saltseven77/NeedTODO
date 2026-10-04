"""Generate launcher assets from the existing NeedTODO potato, without redesigning it."""
from pathlib import Path
from PIL import Image, ImageDraw
import json
import sys
root=Path(__file__).resolve().parents[1]
source=Image.open(root/'assets/potato.png').convert('RGBA')
def icon(size, transparent=False, scale=.70):
    canvas=Image.new('RGBA',(size,size),(248,247,244,0 if transparent else 255))
    potato=source.resize((round(size*scale),round(size*scale)),Image.Resampling.LANCZOS)
    canvas.alpha_composite(potato,((size-potato.width)//2,(size-potato.height)//2))
    return canvas if transparent else canvas.convert('RGB')
icon(256, transparent=True).save(root/'windows/runner/resources/app_icon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
if '--windows-only' in sys.argv:
    print('Transparent Windows potato icon generated')
    sys.exit(0)
res=root/'android/app/src/main/res'
for density,size in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    folder=res/f'mipmap-{density}';folder.mkdir(parents=True,exist_ok=True)
    icon(size).save(folder/'ic_launcher.png')
    icon(round(size*108/48),True,.60).save(folder/'ic_launcher_foreground.png')
folder=res/'mipmap-anydpi-v26';folder.mkdir(exist_ok=True)
(folder/'ic_launcher.xml').write_text('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/launcher_background"/><foreground android:drawable="@mipmap/ic_launcher_foreground"/></adaptive-icon>',encoding='utf-8')
(res/'values/launcher_colors.xml').write_text('<resources><color name="launcher_background">#f8f7f4</color></resources>',encoding='utf-8')
ios=root/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
manifest=json.loads((ios/'Contents.json').read_text())
for entry in manifest['images']:
    if 'filename' in entry:
        size=round(float(entry['size'].split('x')[0])*float(entry['scale'].rstrip('x')))
        icon(size).save(ios/entry['filename'])
print('Android, iOS and Windows potato icons generated')
