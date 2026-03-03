"""Apply rounded corners to all web/favicon icons from agos_app_icon.png."""
from PIL import Image, ImageDraw
import os

base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(base, 'assets', 'images', 'agos_app_icon.png')

def round_image(img, radius_pct=0.20):
    """Apply rounded corners with radius as fraction of image size."""
    img = img.convert('RGBA')
    w, h = img.size
    radius = int(min(w, h) * radius_pct)
    mask = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, w-1, h-1], radius=radius, fill=255)
    result = img.copy()
    result.putalpha(mask)
    return result

img = Image.open(src).convert('RGBA')

# favicon.png (32x32)
round_image(img.resize((32, 32), Image.LANCZOS)).save(os.path.join(base, 'web', 'favicon.png'))
print('favicon.png done')

# web/icons/
for size in [192, 512]:
    rounded = round_image(img.resize((size, size), Image.LANCZOS))
    rounded.save(os.path.join(base, 'web', 'icons', f'Icon-{size}.png'))
    rounded.save(os.path.join(base, 'web', 'icons', f'Icon-maskable-{size}.png'))
    print(f'Icon-{size}.png + maskable done')

print('All icons updated with rounded corners.')
