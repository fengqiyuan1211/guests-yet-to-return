import copy
import json
from pathlib import Path
import unittest

from cocktail_service.contracts import parse_request
from cocktail_service.prompts import PromptBuilder

ROOT = Path(__file__).resolve().parents[1]


class GarnishWhitelistTests(unittest.TestCase):
    def setUp(self):
        self.builder = PromptBuilder(ROOT)
        self.request = json.loads((ROOT / "examples/request-gin-tonic.json").read_text())

    def build(self, value):
        return self.builder.build(parse_request(value, self.builder.profiles))

    def test_garnish_free_drink_does_not_receive_leaf_reference(self):
        value = copy.deepcopy(self.request)
        value["recipe"]["ingredients"] = [x for x in value["recipe"]["ingredients"] if x["use"] != "装饰"]
        bundle = self.build(value)
        pictures = [x["shot_id"] for x in bundle.metadata["image_roles"] if x["role"] == "style_few_shot"]
        self.assertEqual(pictures, [])  # No garnish-free reference with this selected glass.
        self.assertIn("均不添加水果、叶片", bundle.prompt)
        self.assertIn("没有装饰，也没有留杯固体", bundle.prompt)
        self.assertEqual(bundle.metadata["serving_constraints"]["allowed_visible_ingredients"], [])

    def test_lime_drink_cannot_copy_mojito_mint(self):
        bundle = self.build(self.request)
        pictures = [x["shot_id"] for x in bundle.metadata["image_roles"] if x["role"] == "style_few_shot"]
        self.assertNotIn("mojito", pictures)
        self.assertIn("种类和数量必须一致，不增加、不省略、不替换", bundle.prompt)

    def test_real_mint_in_glass_is_still_allowed(self):
        value = copy.deepcopy(self.request)
        value["recipe"]["ingredients"].append({"sku_id": "sku_mint_leaf", "name": "薄荷叶", "amount": 6, "unit": "piece", "use": "制作香草"})
        value["recipe"]["retained_solids"] = ["sku_mint_leaf"]
        bundle = self.build(value)
        self.assertNotIn("本杯未选择薄荷", bundle.prompt)
        self.assertIn("sku_mint_leaf", [x["sku_id"] for x in bundle.metadata["serving_constraints"]["allowed_visible_ingredients"]])


if __name__ == "__main__":
    unittest.main()
