from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[1]
out=root/'android/app/src/main/res/drawable'
def font(size): return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',size)
ink='#292c32'; muted='#858b94'; accent='#477cae'
def make(name,height):
    image=Image.new('RGBA',(560,height),(0,0,0,0));draw=ImageDraw.Draw(image)
    draw.rounded_rectangle((4,4,556,height-4),radius=24,fill='white')
    if name=='agenda':
        draw.text((28,23),'10月5日 星期一',font=font(23),fill=ink);draw.text((506,13),'+',font=font(36),fill=ink)
        for y,t,title in [(90,'09:30\n10:00','阅读与记录'),(171,'14:00\n15:00','整理本周日程')]:
            draw.multiline_text((28,y),t,font=font(18),fill=muted,spacing=4)
            draw.rectangle((120,y,124,y+55),fill=accent);draw.text((143,y+9),title,font=font(23),fill=ink)
    else:
        draw.text((22,13),'‹',font=font(36),fill=ink);draw.text((506,13),'›',font=font(36),fill=ink)
        draw.text((190,23),'2026年10月',font=font(24),fill=ink)
        for i,label in enumerate('一二三四五六日'):draw.text((42+i*75,76),label,font=font(17),fill=muted)
        for n in range(35):
            number=n-2; x=45+(n%7)*75;y=116+(n//7)*48
            if number<1 or number>31:continue
            if number==5:draw.ellipse((x-8,y-4,x+31,y+35),fill=accent)
            draw.text((x,y),str(number),font=font(21),fill='white' if number==5 else ink)
    image.save(out/f'{name}_widget_preview.png')
make('agenda',274);make('calendar',386)
