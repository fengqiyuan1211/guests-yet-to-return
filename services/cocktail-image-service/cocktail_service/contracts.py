from __future__ import annotations

import base64
import hashlib
import io
import json
import math
import re
from dataclasses import dataclass
from typing import Any

from PIL import Image, UnidentifiedImageError

STYLE_ID = "saloon-cocktail-cutout-v1"
SAFE_ID = re.compile(r"^[A-Za-z0-9_-]{1,80}$")
UNITS = {"ml", "g", "piece", "sprig", "dash"}
ROLES = {"基酒", "配料", "制作香草", "装饰"}
GLASSES = {
    "球形杯": ("balloon", "round balloon Copa glass with an elegant stem and circular foot", 500),
    "高球杯": ("highball", "tall straight-sided highball glass with a solid clear base", 350),
    "碟形杯": ("coupe", "shallow rounded coupe glass with a thin stem and circular foot", 180),
    "鸡尾酒杯": ("cocktail", "classic V-shaped cocktail glass with a thin stem and circular foot", 180),
    "古典杯": ("rocks", "short straight-sided rocks glass with a thick clear base", 300),
}
GLASS_ALIASES = {
    "冷却鸡尾酒杯": "碟形杯", "coupe": "碟形杯", "highball": "高球杯",
    "balloon": "球形杯", "rocks": "古典杯", "cocktail": "鸡尾酒杯",
    "glass_balloon_glass": "球形杯", "glass_highball_glass": "高球杯",
    "glass_saucer_glass": "碟形杯", "glass_cocktail_glass": "鸡尾酒杯",
}


class InputError(ValueError):
    def __init__(self, code: str, message: str, field: str = ""):
        super().__init__(message)
        self.code, self.message, self.field = code, message, field


def text(value: Any, field: str, maximum: int = 100, optional: bool = False) -> str:
    if optional and value is None:
        return ""
    if not isinstance(value, str) or len(value) > maximum or (not optional and not value.strip()):
        raise InputError("invalid_input", f"{field} 需要有效文字，最长 {maximum} 字。", field)
    return value.strip()


def number(value: Any, field: str, maximum: float = 1000) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 < value <= maximum:
        raise InputError("invalid_amount", f"{field} 必须是大于 0、不超过 {maximum:g} 的有限数字。", field)
    return float(value)


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def decode_preview(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or len(value) > 8_000_000 or not value.startswith(("data:image/png;base64,", "data:image/jpeg;base64,")):
        raise InputError("invalid_preview", "预览图需要 PNG/JPEG 的 Base64 data URL，不能填写本机路径或远程 URL。", "preview_image")
    try:
        raw = base64.b64decode(value.split(",", 1)[1], validate=True)
        if len(raw) > 5_000_000:
            raise ValueError("too large")
        with Image.open(io.BytesIO(raw)) as image:
            if image.format not in ("PNG", "JPEG") or image.width * image.height > 8_000_000 or min(image.size) < 16:
                raise ValueError("dimensions")
            image.load()
            # The preview is a color/fill reference. Its crude line work is never
            # a protected geometry mask. Normalize it for the provider only.
            image = image.convert("RGBA")
            image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (1024, 1024), "white")
            canvas.alpha_composite(image, ((1024 - image.width) // 2, (1024 - image.height) // 2))
            output = io.BytesIO()
            canvas.convert("RGB").save(output, "PNG")
        return "data:image/png;base64," + base64.b64encode(output.getvalue()).decode("ascii")
    except (ValueError, OSError, UnidentifiedImageError, Image.DecompressionBombError) as error:
        raise InputError("invalid_preview", "预览图不能解码，或图片尺寸过大。", "preview_image") from error


@dataclass(frozen=True)
class Request:
    request_id: str
    recipe: dict
    recipe_hash: str
    request_hash: str
    preview_image: str | None
    style_id: str = STYLE_ID


def parse_request(data: Any, profiles: dict) -> Request:
    if not isinstance(data, dict) or data.get("schema_version") != 1 or isinstance(data.get("schema_version"), bool):
        raise InputError("invalid_schema", "schema_version 必须为 1。", "schema_version")
    request_id = text(data.get("request_id"), "request_id", 80)
    if not SAFE_ID.fullmatch(request_id):
        raise InputError("invalid_id", "request_id 只能包含英文字母、数字、下划线和短横线。", "request_id")
    if data.get("style_id", STYLE_ID) != STYLE_ID:
        raise InputError("unknown_style", "当前仅支持现有酒馆手绘风格。", "style_id")
    original = data.get("recipe")
    if not isinstance(original, dict):
        raise InputError("invalid_recipe", "recipe 需要一个对象。", "recipe")
    recipe_id = text(original.get("id"), "recipe.id", 80)
    if not SAFE_ID.fullmatch(recipe_id):
        raise InputError("invalid_id", "酒的 id 只能包含英文字母、数字、下划线和短横线。", "recipe.id")
    revision = original.get("revision")
    if isinstance(revision, bool) or not isinstance(revision, int) or not 1 <= revision <= 1_000_000:
        raise InputError("invalid_revision", "recipe.revision 需要从 1 开始的整数。", "recipe.revision")
    glass = text(original.get("glass"), "recipe.glass", 60)
    glass = GLASS_ALIASES.get(glass, glass)
    if glass not in GLASSES:
        raise InputError("unknown_glass", "请使用球形杯、高球杯、碟形杯、鸡尾酒杯或古典杯。", "recipe.glass")
    preparation = text(original.get("preparation"), "recipe.preparation", 300)
    ingredients = original.get("ingredients")
    if not isinstance(ingredients, list) or not 1 <= len(ingredients) <= 32:
        raise InputError("invalid_ingredients", "需要 1–32 条实际使用的原料及装饰。", "recipe.ingredients")
    normalized = []
    keys = set()
    for index, ingredient in enumerate(ingredients):
        field = f"recipe.ingredients[{index}]"
        if not isinstance(ingredient, dict):
            raise InputError("invalid_ingredient", "每条原料需要一个对象。", field)
        sku = text(ingredient.get("sku_id"), field + ".sku_id", 100, optional=True)
        profile = profiles.get(sku, {})
        name = profile.get("name") or text(ingredient.get("name"), field + ".name", 60)
        if sku and not profile:
            raise InputError("unknown_ingredient", "尚未配置这个 SKU 的视觉资料；请核对 SKU 或以名称提交自定义原料。", field + ".sku_id")
        unit = ingredient.get("unit")
        role = ingredient.get("use")
        if unit not in UNITS or role not in ROLES:
            raise InputError("invalid_ingredient", "单位为 ml/g/piece/sprig/dash；用途为基酒/配料/制作香草/装饰。", field)
        if profile.get("is_ice") or "冰块" in name or name in ("方冰", "碎冰", "制作冰", "出品冰"):
            raise InputError("ice_in_ingredients", "冰必须写在独立 ice 数组中。", field)
        amount = number(ingredient.get("amount"), field + ".amount")
        identity = (sku or name, unit, role)
        if identity in keys:
            raise InputError("duplicate_ingredient", "同一用途的同一原料请先合并用量。", field)
        keys.add(identity)
        normalized.append({"sku_id": sku, "name": name, "amount": amount, "unit": unit, "use": role})
    if not any(item["use"] != "装饰" for item in normalized):
        raise InputError("empty_drink", "需要实际酒液或配料，不能只有装饰。", "recipe.ingredients")
    # Canonicalize order for caching; cosmetic JSON ordering must not trigger a
    # second paid request. Never convert unknown dash amounts into ml.
    normalized.sort(key=lambda item: (item["sku_id"], item["name"], item["use"], item["unit"]))
    ice = original.get("ice")
    if not isinstance(ice, list) or len(ice) > 8:
        raise InputError("invalid_ice", "ice 必須是数组；成品无冰时传 []。", "recipe.ice")
    ice_items = []
    for item in ice:
        if not isinstance(item, dict) or item.get("use") not in ("制作冰", "出品冰") or item.get("unit") not in ("g", "piece"):
            raise InputError("invalid_ice", "冰需要 name、amount、unit(g/piece) 和 use(制作冰/出品冰)。", "recipe.ice")
        ice_items.append({"name": text(item.get("name"), "recipe.ice.name", 40), "amount": number(item.get("amount"), "recipe.ice.amount"), "unit": item["unit"], "use": item["use"]})
    retained = original.get("retained_solids")
    if not isinstance(retained, list) or len(retained) > 16:
        raise InputError("invalid_solids", "retained_solids 需要数组；无留杯固体时传 []。", "recipe.retained_solids")
    solids = [text(value, "recipe.retained_solids", 60) for value in retained]
    identities = {x["name"] for x in normalized} | {x["sku_id"] for x in normalized}
    if any(value not in identities for value in solids):
        raise InputError("unknown_solid", "留在杯中的固体必须来自实际配方。", "recipe.retained_solids")
    if len(solids) != len(set(solids)):
        raise InputError("duplicate_solid", "retained_solids 不要重复。", "recipe.retained_solids")
    recipe = {"id": recipe_id, "revision": revision, "name": text(original.get("name"), "recipe.name", 60, optional=True), "story": text(original.get("story"), "recipe.story", 1000, optional=True), "ingredients": normalized, "glass": glass, "preparation": preparation, "ice": sorted(ice_items, key=canonical), "retained_solids": sorted(solids)}
    preview = decode_preview(data.get("preview_image"))
    recipe_hash = hashlib.sha256(canonical(recipe).encode()).hexdigest()
    preview_hash = hashlib.sha256(preview.encode()).hexdigest() if preview else None
    request_hash = hashlib.sha256(canonical({"recipe": recipe, "preview_hash": preview_hash, "style": STYLE_ID}).encode()).hexdigest()
    return Request(request_id, recipe, recipe_hash, request_hash, preview)
