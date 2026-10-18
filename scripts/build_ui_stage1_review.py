"""Generate labeled screenshot comparisons and an offline HTML review index."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw, ImageFont
import html
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'docs/evidence/ui-design-stage1'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font = ImageFont.truetype(FONT, 15)
small = ImageFont.truetype(FONT, 12)

def comparison(name, reference, before, after, android):
    items = [('Supplied reference', reference), ('Before: web 375px', before), ('After: web 393px', after), ('After: Android device', android)]
    canvas = Image.new('RGB', (1040, 650), '#f3f3f3')
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 12), name, font=font, fill='#171717')
    for i,(label,path) in enumerate(items):
        x = 12 + i*260
        draw.text((x, 44), label, font=small, fill='#333333')
        if path.exists():
            im=Image.open(path).convert('RGB')
            im.thumbnail((242,565),Image.Resampling.LANCZOS)
            canvas.paste(im,(x+(242-im.width)//2,72))
        else: draw.text((x,90),'Capture pending',font=small,fill='red')
    target=OUT/'comparisons'/f'{name.lower().replace(" ","-")}.jpg'
    canvas.save(target,quality=90)
    return target

specs = [
 ('Welcome','quickbitetemplate_loginpage.png','18_welcome_mobile.png','393_welcome.png','01_welcome.png'),
 ('Login adaptation','quickbitetemplate_loginpage.png','19_login_mobile.png','393_login.png','02_login.png'),
 ('Discovery','quickbitetemplate_landingpage.png','20_home_list_mobile.png','393_discovery.png','04_discovery.png'),
 ('Restaurant menu','quickbitetemplate_restaurantpage.png','21_menu_mobile.png','393_menu.png','06_menu.png'),
]
comparisons=[]
for name,ref,before,after,android in specs:
    comparisons.append(comparison(name,OUT/'references'/ref,OUT/'before'/before,OUT/'after-web'/after,OUT/'after-android'/android))
# One labeled, shareable overview, preserving screenshot aspect ratios.
contact=Image.new('RGB',(1040,650*4),'white')
for i,p in enumerate(comparisons): contact.paste(Image.open(p),(0,650*i))
contact.save(OUT/'contact-sheet.jpg',quality=88)

def gallery(title,paths):
    figures=''
    for p in paths:
        relative=p.relative_to(OUT).as_posix()
        figures+=f'<figure><a href="{html.escape(relative)}"><img loading="lazy" src="{html.escape(relative)}"></a><figcaption>{html.escape(p.stem)}</figcaption></figure>'
    return f'<section><h2>{html.escape(title)}</h2><div class="gallery">{figures}</div></section>'

body='''<header><p class="eyebrow">QUICKBITE · STAGE 1</p><h1>Food first. Ready for your review.</h1>
<p>Four reconstructed Flutter screens. Real API records. Real food photography.</p>
<p><strong>Not a pixel-perfect claim.</strong> The template uses third-party branding, offers and service metrics that QuickBite does not support. Login is a functional adaptation of its welcome aesthetic. Desktop is an intentional adaptation.</p>
<nav><a href="#comparisons">Comparisons</a><a href="#web">Web</a><a href="#android">Android</a><a href="VISUAL_SPEC.md">Measured specification</a><a href="REPORT.md">Results & limitations</a><a href="contact-sheet.jpg">Contact sheet</a></nav></header>'''
body+='<div id="comparisons"></div>'+gallery('Reference / before / after comparisons',comparisons)
body+='<div id="web"></div>'
for width in [360,393,768,1280,1440]:
    body+=gallery(f'Actual web — {width}px',sorted((OUT/'after-web').glob(f'{width}_*.png')))
body+='<div id="android"></div>'+gallery('Actual Android emulator — 1080×2400 physical, 420dpi',sorted(p for p in (OUT/'after-android').glob('*.png') if 'diagnostic' not in p.name))
body+=gallery('Preserved before screenshots',sorted((OUT/'before').glob('*.png')))
body+='<section><h2>Verification logs</h2><ul>'
for p in sorted((OUT/'logs').glob('*')):
    if p.suffix in ['.txt','.json','.md']: body+=f'<li><a href="logs/{p.name}">{html.escape(p.name)}</a></li>'
body+='</ul></section>'
css='''*{box-sizing:border-box}body{margin:0;background:#f5f5f5;color:#171717;font:15px/1.6 system-ui,sans-serif}header,section{max-width:1400px;margin:auto;padding:32px}header{background:#151515;color:white;border-radius:0 0 28px 28px}h1{font-size:clamp(32px,5vw,60px);line-height:1.05;letter-spacing:-2px;max-width:800px}h2{font-size:23px}.eyebrow{color:#ff8575;font-weight:800;letter-spacing:3px}nav{display:flex;gap:12px;flex-wrap:wrap}a{color:#bc2818}nav a{color:white;border:1px solid #666;padding:8px 14px;border-radius:24px;text-decoration:none}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:18px}figure{margin:0;background:white;padding:12px;border:1px solid #ddd;border-radius:16px;min-width:0}img{display:block;width:100%;max-height:650px;object-fit:contain;object-position:top}figcaption{font-size:12px;color:#555;padding-top:8px}#comparisons+.gallery{grid-template-columns:1fr}section:has(img[src^="comparisons"] ) .gallery{grid-template-columns:repeat(auto-fit,minmax(440px,1fr))}@media(max-width:600px){header,section{padding:20px}section:has(img[src^="comparisons"]) .gallery{grid-template-columns:1fr}}'''
(OUT/'index.html').write_text(f'<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>QuickBite — Stage 1 review</title><style>{css}</style><body>{body}</body></html>')
print('Review:',OUT/'index.html')
