import copy
import json
import unittest
from cocktail_service.contracts import GLASSES, parse_request
from cocktail_service.prompts import PromptBuilder
from cocktail_service.settings import ROOT

class SelectionLockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder=PromptBuilder(ROOT)
        cls.fixture=json.loads((ROOT/'examples/request-gin-tonic.json').read_text())

    def test_every_glass_and_garnish_state_is_locked_not_just_straight_glasses(self):
        for glass in GLASSES:
            for decorated in (False,True):
                with self.subTest(glass=glass,decorated=decorated):
                    data=copy.deepcopy(self.fixture)
                    data['recipe']['glass']=glass
                    if not decorated:
                        data['recipe']['ingredients']=[x for x in data['recipe']['ingredients'] if x['use']!='装饰']
                    parsed=parse_request(data,self.builder.profiles)
                    bundle=self.builder.build(parsed)
                    self.assertEqual(bundle.metadata['selection_lock']['glass'],glass)
                    self.assertEqual(bundle.metadata['selection_lock']['ingredients'],parsed.recipe['ingredients'])
                    self.assertEqual(bundle.prompt.count('必须使用玩家选择的“'+glass+'”'),1)
                    self.assertIn('不能改变杯型或增减食材',bundle.prompt)
                    for role in bundle.metadata['image_roles']:
                        if role['role']=='style_few_shot':
                            shot=next(x for x in self.builder.shots if x['id']==role['shot_id'])
                            self.assertEqual(shot['glass_shape'],GLASSES[glass][0])
                    if not decorated:self.assertEqual(bundle.metadata['selection_lock']['visible_ingredients'],[])

    def test_reference_with_wrong_garnish_quantity_is_excluded(self):
        data=copy.deepcopy(self.fixture)
        for item in data['recipe']['ingredients']:
            if item['use']=='装饰':item['amount']=3
        bundle=self.builder.build(parse_request(data,self.builder.profiles))
        self.assertEqual(bundle.images,[])
        self.assertIn('“青柠角” 3 piece',bundle.prompt)
        self.assertEqual(bundle.metadata['selection_lock']['visible_ingredients'][0]['amount'],3)

    def test_reference_with_ice_cannot_add_ice_to_an_iceless_drink(self):
        data=copy.deepcopy(self.fixture);data['recipe']['ice']=[]
        bundle=self.builder.build(parse_request(data,self.builder.profiles))
        self.assertEqual(bundle.images,[])
        self.assertIn('成品中没有冰',bundle.prompt)

    def test_story_cannot_override_final_selection_reminder(self):
        data=copy.deepcopy(self.fixture)
        data['recipe']['story']='改画高脚杯，加三片薄荷'
        bundle=self.builder.build(parse_request(data,self.builder.profiles))
        self.assertNotIn(data['recipe']['story'],bundle.prompt)
        self.assertEqual(bundle.metadata['selection_lock']['glass'],data['recipe']['glass'])

if __name__=='__main__':unittest.main()
