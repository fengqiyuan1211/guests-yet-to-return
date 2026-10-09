"""Synchronize the JSON catalog into the existing SQLite cross-check database.
Usage: python3 tools/sync_cocktail_sqlite.py
Godot reads JSON; SQLite is an inspection copy, not a second player-state database.
"""
from pathlib import Path
import json
import sqlite3

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'data/cocktails'


def sync():
    catalog = json.loads((DIRECTORY / 'catalog.json').read_text())
    rows = catalog['cocktails']
    assert len({r['id'] for r in rows}) == len(rows)
    connection = sqlite3.connect(DIRECTORY / 'cocktails.sqlite3')
    connection.execute('PRAGMA foreign_keys = ON')
    def dump(value):
        return json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    def insert(table, values):
        keys = list(values)
        sql = f"INSERT INTO {table} ({','.join(keys)}) VALUES ({','.join('?' for _ in keys)})"
        connection.execute(sql, [values[k] for k in keys])
    try:
        with connection:
            for table in ['cocktail_sources','source_references','cocktail_unlock_reference','cocktail_equipment','cocktail_tags','cocktail_steps','cocktail_codex_presentation','cocktail_ice','cocktail_ingredients','cocktails','metadata']:
                connection.execute(f'DELETE FROM {table}')
            for key,value in catalog.items():
                if key != 'cocktails': insert('metadata', {'key':key, 'value_json':dump(value)})
            for reference in catalog['source']['references']:
                insert('source_references', {'id':reference['id'],'name':reference['name'],'scope':reference['scope'],'citation':reference['citation'],'source_sheet_row':reference['sheet_row']})
            fields = ['id','source_id','source_code','name','english_name','type','image_path','alcohol_intensity','sweetness','sourness','bitterness','scores_status','scores_basis','recipe_status','recipe_review_status','glass','glass_status','equipment_status']
            ingredient_fields = ['id','sku_id','ingredient_id','name','use','amount','unit','required','inventory_unit','conversion_factor','conversion_status','inventory_amount','specification','specification_status','quantity_status','quantity_basis','step_reference','note','source_sheet_row']
            step_fields = ['number','operation','instruction','equipment','min_seconds','max_seconds','planned_image_path','image_status','source_image_status','source_sheet_row']
            for record in rows:
                parent = {k:record.get(k) for k in fields}
                parent.update(source_sheet_row=record['source']['row'],record_json=dump(record))
                insert('cocktails', parent)
                for position,item in enumerate(record['ingredients'],1):
                    values = {k:item.get(k) for k in ingredient_fields}
                    values.update(cocktail_id=record['id'],position=position)
                    insert('cocktail_ingredients',values)
                for position,item in enumerate(record.get('ice',[]),1):
                    values = {k:item.get(k) for k in ['id','name','use','amount','unit','inventory_policy','source_sheet_row']}
                    values.update(cocktail_id=record['id'],position=position,record_json=dump(item))
                    insert('cocktail_ice',values)
                insert('cocktail_codex_presentation',{'cocktail_id':record['id'],'codex_order':record['codex_order'],'decoration_id':record['decoration_id'],'preparation':record['preparation'],'story':record['story'],'display_equipment_json':dump(record['display_equipment']),'display_steps_json':dump(record['display_steps']),'story_sources_json':dump(record.get('story_sources',[]))})
                for item in record.get('steps',[]):
                    values = {k:item.get(k) for k in step_fields}
                    values['cocktail_id'] = record['id']
                    insert('cocktail_steps',values)
                for kind,key in [('flavor','flavor_tags'),('mouthfeel','mouthfeel_tags'),('theme','theme_tags')]:
                    for position,text in enumerate(record.get(key) or [],1):
                        insert('cocktail_tags',{'cocktail_id':record['id'],'kind':kind,'position':position,'value':text})
                for position,name in enumerate(record.get('equipment',[]),1):
                    insert('cocktail_equipment',{'cocktail_id':record['id'],'position':position,'name':name})
                unlock = record['unlock']
                insert('cocktail_unlock_reference',dict({'cocktail_id':record['id']},**{k:unlock.get(k) for k in ['value','status','source_value','rule','scope']}))
                for reference in record['provenance'].get('source_references',[]):
                    insert('cocktail_sources',{'cocktail_id':record['id'],'reference_id':reference})
            assert connection.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
            assert not connection.execute('PRAGMA foreign_key_check').fetchall()
        print(json.dumps({'synced':len(rows),'model':catalog.get('sensory_model_version')},ensure_ascii=False))
    finally:
        connection.close()

if __name__ == '__main__':
    sync()
