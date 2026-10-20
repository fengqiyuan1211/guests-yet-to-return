from __future__ import annotations

import base64
import hashlib
import io
import json
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from .contracts import GLASSES, Request

PROMPT_VERSION = "diy-cocktail-compact-v8"

# Approximate illustration proportions for the bowl/body, excluding any stem.
# These guide drawings; they are not physical glassware standards or validators.
GLASS_ART_HINTS = {
    "rocks": ([0.9, 1.25], "矮宽直壁、厚玻璃底、没有杯脚；杯身高度与最大宽度接近，不能画成细长高球杯。"),
    "highball": ([1.7, 2.3], "高而窄的直壁杯、有清晰杯底、没有杯脚；不能替换成矮宽古典杯。"),
    "balloon": ([0.75, 1.05], "圆鼓的球形杯肚、收拢的杯口、细杯脚和圆底座；不能画成直壁长杯。"),
    "coupe": ([0.3, 0.5], "浅而宽的圆弧杯肚、细杯脚和圆底座；不能画成深球形杯肚或直壁长杯。"),
    "cocktail": ([0.65, 0.85], "清楚的V形杯肚、细杯脚和圆底座；不能画成圆弧碟形杯或直壁杯。"),
}

# The complete frozen recipes and expected visuals remain in metadata. Short
# prose teaches recipe-to-appearance behavior without inviting an illustrated
# recipe sheet, labelled diagram, or montage of the reference drinks.
EXAMPLE_LESSONS = {
    "last_word": "经过过滤的制作用冰不出现在成品中；未选装饰就不添加装饰。",
    "mojito": "成品仅保留实际指定的固体，材料的香味不授权增加装饰；装饰数量遵循所选单位。",
    "gin_and_tonic": "近乎无色的原料不会因风味名称自动变成有色酒液或额外的植物。",
    "long_island_iced_tea": "有色配料按实际稀释比例影响酒液颜色；冰和装饰只服从本次真实选择。",
    "manhattan": "少量苦精不使整杯变黑；制作用冰与所选装饰按过滤后的实际状态呈现。",
}


def quoted(value: str) -> str:
    """Keep user data in a single quoted sentence, never as prompt sections."""
    value = " ".join(value.split()).replace("“", "‘").replace("”", "’")
    return f"“{value}”"


def ingredient_phrase(item: dict) -> str:
    # Retain the exact value and original unit: dash is never converted to ml,
    # nor are weight-based garnish or ice quantities invented as item counts.
    amount = item["amount"]
    amount_text = str(int(amount)) if float(amount).is_integer() else str(amount)
    return f'{quoted(item["name"])} {amount_text} {item["unit"]}'


def serving_constraints(recipe: dict, appearance: dict) -> dict:
    """Describe allowed visible contents without guessing counts from weights."""
    identities = {key: item for item in recipe["ingredients"]
                  for key in (item["name"], item["sku_id"]) if key}
    visible = {}
    for item in appearance["visible_garnishes"] + [identities[key] for key in recipe["retained_solids"]]:
        visible[(item["sku_id"], item["name"], item["use"], item["unit"])] = dict(item)
    names = " ".join(item["name"] for item in visible.values()).casefold()
    examples = {
        "薄荷": ("薄荷", "mint"),
        "青柠角": ("青柠角", "lime wedge"),
        "青柠片": ("青柠片", "lime wheel", "lime slice"),
        "柠檬片": ("柠檬片", "lemon slice", "lemon wheel"),
        "鸡尾酒樱桃": ("樱桃", "cherry", "cherries"),
        "吸管": ("吸管", "straw"),
        "装饰签": ("装饰签", "cocktail pick", "skewer"),
    }
    forbidden = [name for name, aliases in examples.items() if not any(alias in names for alias in aliases)]
    ice = [dict(item) for item in appearance["serving_ice"]]
    ratios, shape_hint = GLASS_ART_HINTS[appearance["glass_shape"]]
    return {
        "glass": {"name": recipe["glass"], "shape": appearance["glass_shape"],
                  "height_to_width_hint": list(ratios), "ratio_scope": "body_excluding_stem",
                  "shape_hint": shape_hint, "ratio_basis": "game_art_hint_not_physical_standard"},
        "allowed_visible_ingredients": list(visible.values()),
        "forbidden_garnish_examples": forbidden,
        "serving_ice": ice,
        "piece_count_ice": [item for item in ice if item["unit"] == "piece"],
    }


@dataclass(frozen=True)
class PromptBundle:
    prompt: str
    images: list[str]
    seed: int
    metadata: dict


class PromptBuilder:
    def __init__(self, root: Path, reference_images: bool = True):
        self.root = root
        self.reference_images = reference_images
        self.profiles = json.loads((root / "config/visual_profiles.json").read_text(encoding="utf-8"))
        self.shots = json.loads((root / "config/few_shots.json").read_text(encoding="utf-8"))
        if len(self.shots) != 5:
            raise ValueError("五款 few-shot 资料不完整。")
        self._images = {}
        for shot in self.shots:
            path = root / shot["image_file"]
            raw = path.read_bytes()
            if hashlib.sha256(raw).hexdigest() != shot["image_sha256"]:
                raise ValueError("few-shot 参考图与登记的风格版本不一致。")
            with Image.open(io.BytesIO(raw)) as image:
                image = image.convert("RGBA")
                image.thumbnail((768, 768), Image.Resampling.LANCZOS)
                canvas = Image.new("RGBA", (768, 768), "white")
                canvas.alpha_composite(image, ((768-image.width)//2, (768-image.height)//2))
                out = io.BytesIO()
                canvas.convert("RGB").save(out, "PNG")
            self._images[shot["id"]] = "data:image/png;base64," + base64.b64encode(out.getvalue()).decode("ascii")

    def appearance(self, recipe: dict) -> dict:
        liquids = [x for x in recipe["ingredients"] if x["unit"] == "ml" and x["use"] != "装饰"]
        volume = sum(x["amount"] for x in liquids)
        known = [(x, self.profiles.get(x["sku_id"], {})) for x in liquids]
        colors = [(x["amount"], p["rgb"]) for x, p in known if p.get("rgb")]
        rgb = [round(sum(amount*c[i] for amount, c in colors)/sum(a for a, _ in colors)) for i in range(3)] if colors else [235, 235, 225]
        garnishes = [x for x in recipe["ingredients"] if x["use"] == "装饰"]
        serving_ice = [x for x in recipe["ice"] if x["use"] == "出品冰"]
        profile_hints = [self.profiles[x["sku_id"]]["visual_hint"] for x in recipe["ingredients"] if x["sku_id"] in self.profiles]
        unknown = [x["name"] for x in recipe["ingredients"] if not x["sku_id"]]
        shape, description, capacity = GLASSES[recipe["glass"]]
        return {
            "glass_shape": shape, "glass_description": description,
            "liquid_volume_ml": round(volume, 3),
            "approximate_palette_rgb": rgb,
            "palette_basis": "approximate game palette for reference selection only; output color may be artistically beautified from the actual recipe",
            "fill_hint": "fill level is artistically flexible; neither a full glass nor exact preview fill is required; never add ingredients to fill space",
            "glass_capacity_art_hint_ml": capacity,
            "sparkling": any(self.profiles.get(x["sku_id"], {}).get("sparkling") for x in recipe["ingredients"]),
            "visible_garnishes": garnishes, "serving_ice": serving_ice,
            "retained_solids": recipe["retained_solids"], "ingredient_visual_hints": profile_hints,
            "unmapped_ingredients": unknown,
        }

    def build(self, request: Request) -> PromptBundle:
        appearance = self.appearance(request.recipe)
        constraints = serving_constraints(request.recipe, appearance)
        # Prevent reference garnish from becoming an unintended target garnish.
        # Keep two text lessons, but send pictures only when their visible food
        # is a subset of what the actual finished glass authorizes.
        target_visible = {item["sku_id"] or item["name"] for item in constraints["allowed_visible_ingredients"]}
        def visible_ids(shot):
            value = shot["recipe"]
            retained = set(value.get("retained_solids", []))
            return {item["sku_id"] or item["name"] for item in value["ingredients"]
                    if item["use"] == "装饰" or item["sku_id"] in retained or item["name"] in retained}
        def distance(shot):
            added_garnish = len(visible_ids(shot) - target_visible)
            shape_penalty = 0 if shot["glass_shape"] == appearance["glass_shape"] else 90_000
            color = sum((a-b)**2 for a, b in zip(appearance["approximate_palette_rgb"], shot["rgb"]))
            return added_garnish, shape_penalty + color, shot["id"]
        selected = sorted(self.shots, key=distance)[:2]
        images, image_roles = [], []
        if request.preview_image:
            images.append(request.preview_image)
            image_roles.append({"index": 1, "role": "rule_preview", "instruction": "Selected glass geometry and actual serving contents reference; preserve glass type, stem presence, visible ingredient identities and counts exactly; only color, fill and rendering style may be beautified"})
        def visible_signature(items):
            return sorted((x["sku_id"] or x["name"], x["amount"], x["unit"]) for x in items)
        def compatible_reference(shot):
            if shot["glass_shape"] != appearance["glass_shape"]:
                return False
            shot_appearance = self.appearance(shot["recipe"])
            shot_constraints = serving_constraints(shot["recipe"], shot_appearance)
            return (visible_signature(shot_constraints["allowed_visible_ingredients"])
                    == visible_signature(constraints["allowed_visible_ingredients"])
                    and bool(shot_appearance["serving_ice"]) == bool(appearance["serving_ice"]))
        if self.reference_images:
            for shot in selected:
                if not compatible_reference(shot):
                    continue
                images.append(self._images[shot["id"]])
                image_roles.append({"index": len(images), "role": "style_few_shot", "shot_id": shot["id"], "sha256": shot["image_sha256"]})
                if request.preview_image:
                    break  # Keep the actual cup dominant over example cocktails.
        demonstrations = [{"example_id": shot["id"], "recipe": shot["recipe"], "expected_visual": shot["expected_visual"]} for shot in selected]
        recipe = request.recipe
        contents = [item for item in recipe["ingredients"] if item["use"] != "装饰"]
        garnish = appearance["visible_garnishes"]
        serving_ice = appearance["serving_ice"]
        preparation_ice = [item for item in recipe["ice"] if item["use"] == "制作冰"]
        identities = {key: item for item in recipe["ingredients"] for key in (item["name"], item["sku_id"]) if key}
        retained = [ingredient_phrase(identities[key]) for key in recipe["retained_solids"]]
        allowed = constraints["allowed_visible_ingredients"]
        inventory_sentence = "；".join(ingredient_phrase(item) for item in allowed) if allowed else "无"
        # A drawing brief, not a recipe card: state each fact once, with no
        # repeated manifests or raw story text that the model might typeset.
        paragraphs = [
            "只生成一张无字的单杯鸡尾酒游戏素材，不是配方卡或说明页。画面中只有酒杯与实际杯中内容，任何位置都不出现文字、数字、标签、签名或水印。",
            "必须使用玩家选择的" + quoted(recipe["glass"]) + "：" + constraints["glass"]["shape_hint"]
            + "保持该杯型的轮廓、杯身结构和杯脚有无，不换成其他杯型。",
            "酒液由" + "、".join(ingredient_phrase(item) for item in contents)
            + "混合而成。用量只帮助判断酒液外观，不能写在图上。液体原料不画成其原水果或植物。",
            ("可见装饰和留杯固体仅有：" + inventory_sentence + "。种类和数量必须一致，不增加、不省略、不替换。")
            if allowed else "没有装饰，也没有留杯固体。杯口、杯内、杯旁均不添加水果、叶片、花、吸管或其他物件。",
            ("出品冰仅有：" + "、".join(ingredient_phrase(item) for item in serving_ice)
             + "。按件记录的数量必须一致；按重量记录的不换算成固定块数。制作冰不画入成品。")
            if serving_ice else "成品中没有冰，不画冰块。",
            " ".join(dict.fromkeys(appearance["ingredient_visual_hints"])),
            "注意，酒液颜色必须和配料实际调出颜色基本一致、液位和光影可以自然美化，不要求装满，但不能改变杯型或增减食材。"
            + ("有细小自然气泡。" if appearance["sparkling"] else "不添加气泡。"),
            "钢笔淡彩与彩铅手绘插画风：细而略不规则的深棕轮廓，轻盈水彩、少量排线，克制高光。完整单杯居中，占画面高度约七成，四周留白，不裁切杯口或杯底。",
        ]
        if request.preview_image:
            paragraphs.append("第1张图是本杯规则预览，仅参考所选杯型和实际内容，重新绘成上述画风；颜色和液位可美化。若有冲突，以本次配方为准。")
        style_indices = [str(role["index"]) for role in image_roles if role["role"] == "style_few_shot"]
        if style_indices:
            paragraphs.append("第" + "、".join(style_indices) + "张图只参考笔触，不复制范例的内容、文字或背景。")
        # Keep stories in the job record; send only a bounded visual mood, never
        # names, numbers, narrative objects or instructions to put on the image.
        story = recipe.get("story", "")
        if any(word in story for word in ("安静", "平静", "思念", "怀念", "难过", "孤独", "温柔")):
            paragraphs.append("光感柔和安静，不添加叙事物件。")
        elif any(word in story for word in ("开心", "快乐", "热闹", "庆祝", "明快", "活力")):
            paragraphs.append("光感清透明快，不添加叙事物件。")
        paragraphs.append("最终只要酒的插画。杯外及画面四角、四边全部纯白 RGB(255,255,255)，无纸纹、边框、投影、桌面或背景场景。绝对不要把上面的配方、用量或说明绘制成文字。")
        prompt = "\n\n".join(paragraph for paragraph in paragraphs if paragraph)
        seed = int(request.request_hash[:8], 16) % 2_147_483_648
        metadata = {"prompt_version": PROMPT_VERSION, "style_id": request.style_id,
                    "generation_intent": "redraw", "preview_role": "actual_contents_reference" if request.preview_image else "none",
                    "preview_content_policy": "strict_ingredients_flexible_color_and_fill",
                    "few_shot_ids": [x["id"] for x in selected], "image_roles": image_roles,
                    "reference_garnish_policy": "only_visible_ingredients_authorized_by_target",
                    "reference_selection_policy": "same_glass_exact_visible_ingredients_and_counts_same_ice_presence",
                    "selection_lock": {"glass": recipe["glass"], "ingredients": recipe["ingredients"], "visible_ingredients": allowed, "serving_ice": serving_ice},
                    "reference_count": len(images), "provider_mode": "image_conditioned_generation" if images else "text_to_image",
                    "seed": seed, "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
                    "story_role": "subtle_mood_only" if request.recipe.get("story") else "none",
                    "appearance": appearance, "target_recipe": request.recipe,
                    "few_shot_examples": demonstrations, "serving_constraints": constraints}
        return PromptBundle(prompt, images, seed, metadata)
