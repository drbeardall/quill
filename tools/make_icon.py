"""Draw Quill's app icon (indigo rounded square + white microphone) into an .iconset folder."""
import sys
from pathlib import Path

from AppKit import (
    NSBezierPath, NSBitmapImageFileTypePNG, NSBitmapImageRep, NSCalibratedRGBColorSpace, NSColor,
    NSCompositingOperationSourceAtop, NSCompositingOperationSourceOver, NSGradient, NSGraphicsContext,
    NSImage, NSImageSymbolConfiguration, NSRectFillUsingOperation,
)

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)


def white_symbol(px: float) -> NSImage:
    conf = NSImageSymbolConfiguration.configurationWithPointSize_weight_(px, 0.3)
    sym = NSImage.imageWithSystemSymbolName_accessibilityDescription_("mic.fill", None).imageWithSymbolConfiguration_(conf)
    tinted = sym.copy()
    tinted.lockFocus()
    NSColor.whiteColor().set()
    NSRectFillUsingOperation(((0, 0), tinted.size()), NSCompositingOperationSourceAtop)
    tinted.unlockFocus()
    return tinted


def draw(size: int) -> bytes:
    rep = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, size, size, 8, 4, True, False, NSCalibratedRGBColorSpace, 0, 0
    )
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.setCurrentContext_(NSGraphicsContext.graphicsContextWithBitmapImageRep_(rep))
    inset = size * 0.09
    rect = ((inset, inset), (size - 2 * inset, size - 2 * inset))
    path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(rect, size * 0.2, size * 0.2)
    top = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.36, 0.42, 1.0, 1)
    bottom = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.16, 0.21, 0.66, 1)
    NSGradient.alloc().initWithStartingColor_endingColor_(top, bottom).drawInBezierPath_angle_(path, -90)
    sym = white_symbol(size * 0.4)
    w, h = sym.size()
    sym.drawInRect_fromRect_operation_fraction_(
        (((size - w) / 2, (size - h) / 2), (w, h)), ((0, 0), (0, 0)), NSCompositingOperationSourceOver, 1.0
    )
    NSGraphicsContext.restoreGraphicsState()
    return bytes(rep.representationUsingType_properties_(NSBitmapImageFileTypePNG, {}))


for base in (16, 32, 128, 256, 512):
    (out / f"icon_{base}x{base}.png").write_bytes(draw(base))
    (out / f"icon_{base}x{base}@2x.png").write_bytes(draw(base * 2))
print("icon drawn")
