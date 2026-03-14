from PIL import Image, ImageDraw

w, h = 1400, 900
img = Image.new('RGB', (w, h), (244, 248, 251))
d = ImageDraw.Draw(img)

card = (80, 80, 1320, 780)
d.rounded_rectangle(card, radius=32, fill=(255, 255, 255), outline=(226, 232, 240), width=2)
d.text((130, 125), 'Historical Trends: 7D Rollup View', fill=(28, 44, 60))
d.text((130, 160), 'Average line + min/max band', fill=(100, 116, 139))

left, top, right, bottom = 150, 240, 1260, 700
d.line((left, bottom, right, bottom), fill=(203, 213, 225), width=2)
d.line((left, top, left, bottom), fill=(203, 213, 225), width=2)

n = 7
xs = [left + i * (right - left) // (n - 1) for i in range(n)]
avgs = [420, 390, 460, 430, 360, 405, 385]
spreads = [55, 70, 45, 85, 60, 50, 65]
labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

pts = []
mins = []
maxs = []
for x, avg, spread in zip(xs, avgs, spreads):
    mins.append((x, avg + spread))
    maxs.append((x, avg - spread))
    pts.append((x, avg))

band = maxs + list(reversed(mins))
d.polygon(band, fill=(180, 240, 250))

for i in range(len(xs) - 1):
    d.line((pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]), fill=(43, 127, 255), width=6)

for x, avg, lo, hi, label in zip(xs, avgs, mins, maxs, labels):
    d.line((x, hi[1], x, lo[1]), fill=(0, 211, 242), width=2)
    d.ellipse((x - 7, avg - 7, x + 7, avg + 7), fill=(43, 127, 255))
    d.text((x - 18, bottom + 16), label, fill=(100, 116, 139))

d.text((right - 250, 255), 'Legend', fill=(28, 44, 60))
d.rounded_rectangle((right - 250, 285, right - 30, 405), radius=18, fill=(248, 250, 252), outline=(226, 232, 240))
d.line((right - 220, 320, right - 160, 320), fill=(43, 127, 255), width=6)
d.text((right - 145, 307), 'Average', fill=(51, 65, 85))
d.rectangle((right - 220, 350, right - 160, 374), fill=(180, 240, 250), outline=(0, 211, 242))
d.text((right - 145, 344), 'Min-Max Range', fill=(51, 65, 85))

tipx, tipy = xs[3] + 30, avgs[3] - 110
d.rounded_rectangle((tipx, tipy, tipx + 210, tipy + 130), radius=14, fill=(255, 255, 255), outline=(226, 232, 240), width=2)
d.text((tipx + 18, tipy + 16), '03/14 14:00', fill=(100, 116, 139))
d.text((tipx + 18, tipy + 46), 'Avg: 4.82 NTU', fill=(43, 127, 255))
d.text((tipx + 18, tipy + 74), 'Min: 4.21 NTU', fill=(0, 184, 219))
d.text((tipx + 18, tipy + 100), 'Max: 5.36 NTU', fill=(109, 40, 217))

out = r'c:\Users\Adrian\agos\chart_rollup_mock.png'
img.save(out)
print(out)
