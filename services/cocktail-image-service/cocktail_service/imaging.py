"""Normalize a generated image to a transparent, centered cocktail PNG.

This checks image structure and background removability, not recipe semantics.
White-background removal is deliberately approximate and must be reviewed.
"""

from __future__ import annotations

from collections import deque
from io import BytesIO
import math
import warnings

from PIL import Image, ImageOps, UnidentifiedImageError


MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_IMAGE_PIXELS = 16 * 1024 * 1024
MARGIN_RATIO = 0.12
NEAR_WHITE_MIN = 245
NEAR_WHITE_SPREAD = 12


class ProcessingError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def _border_indices(width: int, height: int) -> list[int]:
    if width == 1 or height == 1:
        return list(range(width * height))
    border = list(range(width))
    border.extend(range((height - 1) * width, height * width))
    for y in range(1, height - 1):
        border.extend((y * width, y * width + width - 1))
    return border


def _remove_white_background(image: Image.Image, border: list[int]) -> tuple[Image.Image, int]:
    width, height = image.size
    pixels = bytearray(image.tobytes())
    white = bytearray(width * height)
    for index in range(len(white)):
        offset = index * 4
        red, green, blue, alpha = pixels[offset:offset + 4]
        low, high = min(red, green, blue), max(red, green, blue)
        white[index] = int(alpha == 0 or (low >= NEAR_WHITE_MIN and high - low <= NEAR_WHITE_SPREAD))
    corner_indices = (0, width - 1, (height - 1) * width, height * width - 1)
    if not all(white[index] for index in corner_indices) or sum(white[index] for index in border) < len(border) * 0.95:
        raise ProcessingError("unsafe_background", "图片已生成，但背景不符合透明素材要求，暂时无法安全去除。请先查看原图，确认画面后再决定是否重新生成。")
    queue = deque()
    for index in border:
        if white[index] == 1:
            white[index] = 2
            queue.append(index)
    removed = 0
    while queue:
        index = queue.popleft()
        pixels[index * 4 + 3] = 0
        removed += 1
        x = index % width
        if x > 0 and white[index - 1] == 1:
            white[index - 1] = 2
            queue.append(index - 1)
        if x + 1 < width and white[index + 1] == 1:
            white[index + 1] = 2
            queue.append(index + 1)
        if index >= width and white[index - width] == 1:
            white[index - width] = 2
            queue.append(index - width)
        if index + width < len(white) and white[index + width] == 1:
            white[index + width] = 2
            queue.append(index + width)
    return Image.frombytes("RGBA", image.size, bytes(pixels)), removed


def normalize_image(image_bytes: bytes, size: int = 1024) -> tuple[bytes, dict]:
    """Return RGBA PNG bytes and candid image-processing metadata.

Existing transparent edges keep the source alpha, including translucent glass.
Opaque white backgrounds are removed only through edge connectivity; enclosed
white highlights are preserved. Unsafe backgrounds are rejected, not relabeled.
"""
    if isinstance(size, bool) or not isinstance(size, int) or not 16 <= size <= 4096:
        raise ProcessingError("invalid_size", "Output size must be an integer between 16 and 4096 pixels.")
    if not isinstance(image_bytes, bytes) or not image_bytes or len(image_bytes) > MAX_IMAGE_BYTES:
        raise ProcessingError("invalid_image", "Image data is empty, invalid, or exceeds the allowed size.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(image_bytes)) as source:
                source_size = source.size
                if source.width * source.height > MAX_IMAGE_PIXELS or getattr(source, "is_animated", False):
                    raise ProcessingError("invalid_image", "A static image within the allowed resolution is required.")
                source.load()
                image = ImageOps.exif_transpose(source).convert("RGBA")
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError, EOFError, Image.DecompressionBombError,
            Image.DecompressionBombWarning):
        raise ProcessingError("invalid_image", "Image data could not be decoded safely.") from None
    width, height = image.size
    border = _border_indices(width, height)
    alpha = image.getchannel("A")
    alpha_values = alpha.tobytes()
    corners = (0, width - 1, (height - 1) * width, height * width - 1)
    clear_alpha_edges = (all(alpha_values[index] == 0 for index in corners)
                         and sum(alpha_values[index] == 0 for index in border) >= len(border) * 0.95)
    removed = 0
    if clear_alpha_edges:
        background_method = "preserved_alpha"
    else:
        image, removed = _remove_white_background(image, border)
        background_method = "edge_connected_near_white"
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ProcessingError("empty_image", "The image contains no visible subject after background processing.")
    subject = image.crop(bounds)
    margin = math.ceil(size * MARGIN_RATIO)
    usable = size - margin * 2
    scale = min(usable / subject.width, usable / subject.height)
    target = (max(1, min(usable, round(subject.width * scale))),
              max(1, min(usable, round(subject.height * scale))))
    if target != subject.size:
        subject = subject.resize(target, Image.Resampling.LANCZOS)
    output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    placement = ((size - subject.width) // 2, (size - subject.height) // 2)
    output.alpha_composite(subject, placement)
    out = BytesIO()
    output.save(out, format="PNG")
    metadata = {
        "alpha": True,
        "background_method": background_method,
        "needs_review": True,
        "semantic_validation": "not_performed",
        "source_size": list(source_size),
        "output_size": [size, size],
        "margin_ratio": MARGIN_RATIO,
        "margin_pixels": margin,
        "subject_bounds": list(output.getchannel("A").getbbox()),
        "removed_background_pixels": removed,
        "review_reasons": (["white_background_removal_is_approximate"]
                           if background_method == "edge_connected_near_white" else [])
                          + ["recipe_appearance_not_verified"],
    }
    return out.getvalue(), metadata
