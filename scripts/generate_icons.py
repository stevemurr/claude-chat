#!/usr/bin/env python3
"""Generate app icons for ClaudeChat."""

import os
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Installing Pillow...")
    os.system("pip3 install Pillow --break-system-packages")
    from PIL import Image, ImageDraw, ImageFont

def create_icon(size: int) -> Image.Image:
    """Create a chat bubble icon with gradient background."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background gradient (coral/orange to pink)
    for y in range(size):
        ratio = y / size
        r = int(255 * (1 - ratio * 0.3))  # 255 -> 178
        g = int(140 - ratio * 60)          # 140 -> 80
        b = int(100 + ratio * 80)          # 100 -> 180
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    # Add rounded corners by masking
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    corner_radius = size // 4
    mask_draw.rounded_rectangle(
        [(0, 0), (size - 1, size - 1)],
        radius=corner_radius,
        fill=255
    )
    img.putalpha(mask)

    # Draw chat bubble
    bubble_margin = size // 6
    bubble_left = bubble_margin
    bubble_top = bubble_margin
    bubble_right = size - bubble_margin
    bubble_bottom = size - bubble_margin - size // 8
    bubble_radius = size // 8

    # Main bubble (white)
    draw.rounded_rectangle(
        [(bubble_left, bubble_top), (bubble_right, bubble_bottom)],
        radius=bubble_radius,
        fill=(255, 255, 255, 255)
    )

    # Bubble tail (bottom left)
    tail_points = [
        (bubble_left + size // 8, bubble_bottom - size // 20),
        (bubble_left + size // 16, bubble_bottom + size // 8),
        (bubble_left + size // 4, bubble_bottom - size // 20)
    ]
    draw.polygon(tail_points, fill=(255, 255, 255, 255))

    # Draw three dots inside bubble
    dot_y = (bubble_top + bubble_bottom) // 2
    dot_radius = size // 20
    dot_spacing = size // 6
    center_x = (bubble_left + bubble_right) // 2

    for i in range(-1, 2):
        dot_x = center_x + i * dot_spacing
        draw.ellipse(
            [(dot_x - dot_radius, dot_y - dot_radius),
             (dot_x + dot_radius, dot_y + dot_radius)],
            fill=(200, 100, 120, 255)
        )

    return img


def main():
    script_dir = Path(__file__).parent.parent
    icon_dir = script_dir / "Shared" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)

    # iOS and macOS icon sizes
    sizes = [
        # iOS
        (20, 1), (20, 2), (20, 3),
        (29, 1), (29, 2), (29, 3),
        (40, 1), (40, 2), (40, 3),
        (60, 2), (60, 3),
        (76, 1), (76, 2),
        (83.5, 2),
        (1024, 1),
        # macOS
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]

    generated = set()
    for base_size, scale in sizes:
        pixel_size = int(base_size * scale)
        if pixel_size in generated:
            continue
        generated.add(pixel_size)

        icon = create_icon(pixel_size)
        filename = f"icon_{pixel_size}x{pixel_size}.png"
        icon.save(icon_dir / filename)
        print(f"Generated {filename}")

    # Create Contents.json
    contents = {
        "images": [
            # iPhone notifications
            {"size": "20x20", "idiom": "iphone", "filename": "icon_40x40.png", "scale": "2x"},
            {"size": "20x20", "idiom": "iphone", "filename": "icon_60x60.png", "scale": "3x"},
            # iPhone settings
            {"size": "29x29", "idiom": "iphone", "filename": "icon_58x58.png", "scale": "2x"},
            {"size": "29x29", "idiom": "iphone", "filename": "icon_87x87.png", "scale": "3x"},
            # iPhone spotlight
            {"size": "40x40", "idiom": "iphone", "filename": "icon_80x80.png", "scale": "2x"},
            {"size": "40x40", "idiom": "iphone", "filename": "icon_120x120.png", "scale": "3x"},
            # iPhone app
            {"size": "60x60", "idiom": "iphone", "filename": "icon_120x120.png", "scale": "2x"},
            {"size": "60x60", "idiom": "iphone", "filename": "icon_180x180.png", "scale": "3x"},
            # iPad notifications
            {"size": "20x20", "idiom": "ipad", "filename": "icon_20x20.png", "scale": "1x"},
            {"size": "20x20", "idiom": "ipad", "filename": "icon_40x40.png", "scale": "2x"},
            # iPad settings
            {"size": "29x29", "idiom": "ipad", "filename": "icon_29x29.png", "scale": "1x"},
            {"size": "29x29", "idiom": "ipad", "filename": "icon_58x58.png", "scale": "2x"},
            # iPad spotlight
            {"size": "40x40", "idiom": "ipad", "filename": "icon_40x40.png", "scale": "1x"},
            {"size": "40x40", "idiom": "ipad", "filename": "icon_80x80.png", "scale": "2x"},
            # iPad app
            {"size": "76x76", "idiom": "ipad", "filename": "icon_76x76.png", "scale": "1x"},
            {"size": "76x76", "idiom": "ipad", "filename": "icon_152x152.png", "scale": "2x"},
            # iPad Pro
            {"size": "83.5x83.5", "idiom": "ipad", "filename": "icon_167x167.png", "scale": "2x"},
            # App Store
            {"size": "1024x1024", "idiom": "ios-marketing", "filename": "icon_1024x1024.png", "scale": "1x"},
            # macOS
            {"size": "16x16", "idiom": "mac", "filename": "icon_16x16.png", "scale": "1x"},
            {"size": "16x16", "idiom": "mac", "filename": "icon_32x32.png", "scale": "2x"},
            {"size": "32x32", "idiom": "mac", "filename": "icon_32x32.png", "scale": "1x"},
            {"size": "32x32", "idiom": "mac", "filename": "icon_64x64.png", "scale": "2x"},
            {"size": "128x128", "idiom": "mac", "filename": "icon_128x128.png", "scale": "1x"},
            {"size": "128x128", "idiom": "mac", "filename": "icon_256x256.png", "scale": "2x"},
            {"size": "256x256", "idiom": "mac", "filename": "icon_256x256.png", "scale": "1x"},
            {"size": "256x256", "idiom": "mac", "filename": "icon_512x512.png", "scale": "2x"},
            {"size": "512x512", "idiom": "mac", "filename": "icon_512x512.png", "scale": "1x"},
            {"size": "512x512", "idiom": "mac", "filename": "icon_1024x1024.png", "scale": "2x"},
        ],
        "info": {"version": 1, "author": "xcode"}
    }

    import json
    with open(icon_dir / "Contents.json", "w") as f:
        json.dump(contents, f, indent=2)

    print(f"\nGenerated Contents.json")
    print(f"Icons saved to: {icon_dir}")


if __name__ == "__main__":
    main()
