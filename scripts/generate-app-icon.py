"""
Generate macOS app icon for Voice Input AI.
Outputs all required sizes for AppIcon.appiconset.
Run once: python3 scripts/generate-app-icon.py
"""

import math
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


# --- Config ---
SIZE = 1024
BG_COLOR_TOP = (79, 142, 247)       # #4F8EF7 blue
BG_COLOR_BOT = (108, 92, 231)       # #6C5CE7 indigo
MIC_COLOR = (255, 255, 255)
WAVE_COLOR = (255, 255, 255)
WAVE_OPACITY = [180, 130, 80]       # decreasing opacity for each wave

OUTPUT_DIR = Path(__file__).parent.parent / "VoiceInput" / "Assets.xcassets" / "AppIcon.appiconset"

# macOS squircle corner ratio (approximation of continuous curvature)
CORNER_RATIO = 0.2235  # ~229/1024


def superellipse_points(cx, cy, w, h, n=200):
    """Generate points for a squircle (superellipse with exponent ~5)."""
    points = []
    exp = 5.0
    for i in range(n):
        t = 2 * math.pi * i / n
        x = cx + w * math.copysign(abs(math.cos(t)) ** (2 / exp), math.cos(t))
        y = cy + h * math.copysign(abs(math.sin(t)) ** (2 / exp), math.sin(t))
        points.append((x, y))
    return points


def draw_gradient_squircle(draw, size):
    """Draw blue-to-indigo gradient background in squircle shape."""
    # Create gradient image
    gradient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        ratio = y / size
        r = int(BG_COLOR_TOP[0] + (BG_COLOR_BOT[0] - BG_COLOR_TOP[0]) * ratio)
        g = int(BG_COLOR_TOP[1] + (BG_COLOR_BOT[1] - BG_COLOR_TOP[1]) * ratio)
        b = int(BG_COLOR_TOP[2] + (BG_COLOR_BOT[2] - BG_COLOR_TOP[2]) * ratio)
        for x in range(size):
            gradient.putpixel((x, y), (r, g, b, 255))

    # Create squircle mask
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    margin = size * 0.02  # small margin
    half = size / 2 - margin
    points = superellipse_points(size / 2, size / 2, half, half)
    mask_draw.polygon(points, fill=255)

    # Apply mask to gradient
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(gradient, (0, 0), mask)
    return result


def draw_microphone(img, size):
    """Draw a stylized microphone icon in the center."""
    draw = ImageDraw.Draw(img)
    cx, cy = size / 2, size * 0.42  # mic slightly above center

    # Mic body dimensions
    mic_w = size * 0.13
    mic_h = size * 0.22
    mic_r = mic_w  # capsule shape = fully rounded top/bottom

    # Mic capsule (rounded rectangle)
    mic_left = cx - mic_w
    mic_top = cy - mic_h
    mic_right = cx + mic_w
    mic_bot = cy + mic_h

    draw.rounded_rectangle(
        [mic_left, mic_top, mic_right, mic_bot],
        radius=mic_r,
        fill=MIC_COLOR,
    )

    # Mic stand (vertical line below capsule)
    stand_w = size * 0.018
    stand_top = mic_bot + size * 0.01
    stand_bot = cy + mic_h + size * 0.1
    draw.rectangle(
        [cx - stand_w, stand_top, cx + stand_w, stand_bot],
        fill=MIC_COLOR,
    )

    # Mic base (horizontal line)
    base_w = size * 0.09
    base_h = size * 0.018
    base_y = stand_bot
    draw.rounded_rectangle(
        [cx - base_w, base_y, cx + base_w, base_y + base_h],
        radius=base_h / 2,
        fill=MIC_COLOR,
    )

    # Mic holder arc (the curved bracket around capsule top)
    holder_r = size * 0.19
    holder_cy = cy + mic_h * 0.15
    holder_w = size * 0.02
    bbox = [
        cx - holder_r, holder_cy - holder_r,
        cx + holder_r, holder_cy + holder_r,
    ]
    draw.arc(bbox, start=20, end=160, fill=MIC_COLOR, width=int(holder_w))

    return img


def draw_sound_waves(img, size):
    """Draw 3 concentric sound wave arcs emanating from mic."""
    draw = ImageDraw.Draw(img)
    cx = size / 2
    cy = size * 0.42

    wave_configs = [
        {"r": size * 0.28, "start": 25, "end": 70, "width": size * 0.022},
        {"r": size * 0.35, "start": 25, "end": 65, "width": size * 0.020},
        {"r": size * 0.42, "start": 25, "end": 60, "width": size * 0.018},
    ]

    # Right side waves
    for i, cfg in enumerate(wave_configs):
        r = cfg["r"]
        overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        overlay_draw = ImageDraw.Draw(overlay)
        bbox = [cx - r, cy - r, cx + r, cy + r]
        overlay_draw.arc(
            bbox,
            start=-cfg["end"],
            end=-cfg["start"],
            fill=(*WAVE_COLOR, WAVE_OPACITY[i]),
            width=int(cfg["width"]),
        )
        img = Image.alpha_composite(img, overlay)

    # Left side waves (mirrored)
    for i, cfg in enumerate(wave_configs):
        r = cfg["r"]
        overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        overlay_draw = ImageDraw.Draw(overlay)
        bbox = [cx - r, cy - r, cx + r, cy + r]
        overlay_draw.arc(
            bbox,
            start=180 + cfg["start"],
            end=180 + cfg["end"],
            fill=(*WAVE_COLOR, WAVE_OPACITY[i]),
            width=int(cfg["width"]),
        )
        img = Image.alpha_composite(img, overlay)

    return img


def add_vignette(img, size):
    """Subtle inner glow / vignette for depth."""
    vignette = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(vignette)

    # Soft dark ring near edge
    margin = size * 0.06
    points = superellipse_points(size / 2, size / 2, size / 2 - margin, size / 2 - margin)
    inverted_mask = Image.new("L", (size, size), 255)
    inv_draw = ImageDraw.Draw(inverted_mask)
    inv_draw.polygon(points, fill=0)

    # Apply subtle darkening
    for y in range(size):
        for x_off in [0, size - 1]:
            # Skip per-pixel for perf — use radial gradient instead
            pass

    # Simpler: just a subtle gradient overlay at edges
    for y in range(size):
        for x in range(0, size, 4):  # sample every 4px for speed
            dx = (x - size / 2) / (size / 2)
            dy = (y - size / 2) / (size / 2)
            dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0.75:
                alpha = int((dist - 0.75) / 0.25 * 30)
                vignette.putpixel((x, y), (0, 0, 0, alpha))

    vignette = vignette.filter(ImageFilter.GaussianBlur(radius=size * 0.03))
    return Image.alpha_composite(img, vignette)


def generate_icon():
    """Generate the master 1024x1024 icon."""
    print(f"Generating {SIZE}x{SIZE} master icon...")

    # Base: gradient squircle
    img = draw_gradient_squircle(None, SIZE)

    # Sound waves (behind mic)
    img = draw_sound_waves(img, SIZE)

    # Microphone
    img = draw_microphone(img, SIZE)

    # Vignette for depth
    img = add_vignette(img, SIZE)

    return img


def save_sizes(master):
    """Save all required macOS icon sizes."""
    # macOS icon size mapping: (logical_size, scale) -> pixel_size
    sizes = [
        ("16x16", "1x", 16),
        ("16x16", "2x", 32),
        ("32x32", "1x", 32),
        ("32x32", "2x", 64),
        ("128x128", "1x", 128),
        ("128x128", "2x", 256),
        ("256x256", "1x", 256),
        ("256x256", "2x", 512),
        ("512x512", "1x", 512),
        ("512x512", "2x", 1024),
    ]

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for logical, scale, px in sizes:
        filename = f"icon_{logical}@{scale}.png"
        resized = master.resize((px, px), Image.LANCZOS)
        filepath = OUTPUT_DIR / filename
        resized.save(filepath, "PNG")
        print(f"  Saved {filename} ({px}x{px})")

    # Also save master for reference
    master.save(OUTPUT_DIR / "icon_master_1024x1024.png", "PNG")
    print(f"  Saved icon_master_1024x1024.png (source)")

    return sizes


def update_contents_json(sizes):
    """Update Contents.json with filename references."""
    contents_path = OUTPUT_DIR / "Contents.json"

    images = []
    for logical, scale, px in sizes:
        filename = f"icon_{logical}@{scale}.png"
        images.append({
            "filename": filename,
            "idiom": "mac",
            "scale": scale,
            "size": logical,
        })

    contents = {
        "images": images,
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }

    import json
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")

    print(f"\nUpdated {contents_path}")


if __name__ == "__main__":
    master = generate_icon()
    sizes = save_sizes(master)
    update_contents_json(sizes)
    print("\nDone! All icons generated.")
