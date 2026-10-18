"""Build a self-contained screenshot contact sheet and final review index."""

from __future__ import annotations

import html
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/evidence/final"
ANDROID = EVIDENCE / "after-android"
WEB = EVIDENCE / "after-web"
REFERENCES = ROOT / "docs/evidence/ui-design-stage1/references"


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = (
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        Path("/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"),
    )
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def comparison_sheet() -> None:
    specs = (
        ("Welcome", "quickbitetemplate_loginpage.png", "01_welcome.png"),
        ("Login adaptation", "quickbitetemplate_loginpage.png", "02_login.png"),
        (
            "Restaurant discovery",
            "quickbitetemplate_landingpage.png",
            "04_discovery.png",
        ),
        ("Restaurant menu", "quickbitetemplate_restaurantpage.png", "06_menu.png"),
    )
    width, height = 1240, 1510
    sheet = Image.new("RGB", (width, height), "#f2f3f5")
    draw = ImageDraw.Draw(sheet)
    title_font, label_font = font(28), font(17)
    draw.text(
        (28, 18),
        "QuickBite · reference and Android emulator",
        font=title_font,
        fill="#161616",
    )
    box_width, box_height = 260, 570
    for index, (label, reference, screenshot) in enumerate(specs):
        col, row = index % 2, index // 2
        x = 20 + col * 610
        y = 70 + row * 710
        draw.text((x, y), label, font=label_font, fill="#202020")
        for offset, path in enumerate((REFERENCES / reference, ANDROID / screenshot)):
            image = Image.open(path).convert("RGB")
            image.thumbnail((box_width, box_height), Image.Resampling.LANCZOS)
            image_x = x + offset * 285 + (box_width - image.width) // 2
            image_y = y + 32 + (box_height - image.height) // 2
            sheet.paste(image, (image_x, image_y))
        draw.text(
            (x + 30, y + 610),
            "TEMPLATE                         ANDROID",
            font=font(12),
            fill="#555",
        )
    sheet.save(EVIDENCE / "contact-sheet.jpg", quality=88)


def image_section(title: str, paths: list[Path]) -> str:
    figures = "".join(
        '<figure><a href="{}"><img loading="lazy" src="{}" alt="{}"></a>'
        "<figcaption>{}</figcaption></figure>".format(
            html.escape(path.relative_to(EVIDENCE).as_posix()),
            html.escape(path.relative_to(EVIDENCE).as_posix()),
            html.escape(path.stem.replace("_", " ")),
            html.escape(path.stem.replace("_", " ")),
        )
        for path in paths
        if path.exists()
    )
    return f"<section><h2>{html.escape(title)}</h2><div class=gallery>{figures}</div></section>"


def main() -> None:
    comparison_sheet()
    # Preserve diagnostic captures for debugging, but keep the review gallery
    # focused on the completed, labeled integration journey.
    android_images = sorted(
        path for path in ANDROID.glob("*.png") if not path.stem.startswith("diagnostic_")
    )
    web_images = sorted(WEB.glob("*.png"))
    logs = sorted(
        path
        for path in EVIDENCE.glob("*")
        if path.is_file() and path.suffix in {".txt", ".json", ".md"}
    )
    links = "".join(
        f'<li><a href="{html.escape(path.name)}">{html.escape(path.name)}</a></li>'
        for path in logs
    )
    content = """<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>QuickBite final review evidence</title><style>
body{margin:0;background:#f4f5f7;color:#171717;font:15px/1.55 system-ui,sans-serif}
header{background:#171717;color:white;padding:36px max(24px,calc((100vw - 1400px)/2));}
h1{font-size:clamp(32px,5vw,56px);line-height:1.05;max-width:900px;margin:12px 0}
header a{color:white;margin-right:16px}main{max-width:1400px;margin:auto;padding:20px 24px}
section{padding:12px 0 28px}h2{font-size:24px}.gallery{display:grid;
grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:18px}
figure{margin:0;background:white;border:1px solid #dedfe3;border-radius:16px;padding:12px}
img{width:100%;height:620px;object-fit:contain;object-position:top;display:block}
figcaption{font-size:13px;color:#50545a;padding-top:8px}
.wide{max-height:none;height:auto}.note{background:white;padding:18px 22px;border-radius:14px}
</style><header><p>QUICKBITE · FULL PROJECT FINALIZATION</p>
<h1>Review the real app output and test evidence</h1>
<p>The final release APK was installed on a physical Android 16 phone. The verified journey reached restaurant discovery, submitted one test order, and confirmed order history and notifications. The database holds 2,000 restaurants and 19,992 menu items.</p>
<nav><a href="#comparisons">Comparisons</a><a href="#android">Android</a>
<a href="#web">Web</a><a href="#tests">Tests and reports</a></nav></header><main>
<section id="comparisons"><h2>Template comparison</h2>
<p>The contact sheet pairs each supplied template with a settled Android emulator frame. The login screen adapts the welcome visual language to a working email/password form.</p>
<a href="contact-sheet.jpg"><img class=wide src="contact-sheet.jpg" alt="Template and Android comparison"></a></section>
<section id="android"><h2>Android · emulator and physical release</h2>
<p>The release APK ran on the connected CPH2793 phone with the local API routed through ADB reverse. One isolated test order reached driver assignment, and its four processing notifications persisted. The focused final screen is below.</p>
<p><a href="../../../frontend/build/app/outputs/flutter-apk/app-release.apk">Release APK artifact</a> · <a href="android-release-runtime-final.txt">Physical runtime record</a> · <a href="android-release-build-final.txt">Release build log</a></p>
<a href="after-android/release-final-orders-physical.png"><img class=wide src="after-android/release-final-orders-physical.png" alt="Physical Android release order history"></a></section>
"""
    content += image_section("Captured Android screens", android_images)
    content += '<section id="web"><h2>Flutter web · nginx and Chrome</h2><p>The current release bundle was served through project nginx. Chrome CDP verified real demo sign-in and loaded the live restaurant discovery screen; SPA route checks are recorded in the logs. Full menu-to-checkout browser automation remains unverified. Android covers the broader authenticated journey.</p></section>'
    content += image_section("Captured web screens", web_images)
    content += (
        '<section id="tests"><h2>Test logs and reports</h2><p><a href="REPORT.md">Final implementation and verification report</a> · <a href="FILES.md">Changed-file manifest</a></p><ul>' + links + "</ul>"
    )
    content += "<div class=note><strong>Verification limits:</strong> iOS could not run on this Linux host. The release APK is signed with the Android debug certificate and configured for a local API reachable through ADB reverse; store signing and deployed HTTPS API verification remain outstanding. Browser automation packages are absent, so the full menu-to-checkout browser journey is unverified.</div></section>"
    content += "</main></html>"
    (EVIDENCE / "index.html").write_text(content)
    print(EVIDENCE / "index.html")


if __name__ == "__main__":
    main()
