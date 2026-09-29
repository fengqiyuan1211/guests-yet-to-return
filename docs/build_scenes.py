"""Author native, editable Godot scenes. Only used to reproduce initial layout."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

def q(value):
    return json.dumps(value, ensure_ascii=False)

def color(hex_value):
    value = hex_value.lstrip('#')
    parts = [int(value[i:i+2], 16) / 255 for i in range(0, len(value), 2)]
    if len(parts) == 3:
        parts.append(1)
    return 'Color(%s)' % ', '.join(f'{v:.4f}' for v in parts)

def style(id, bg, border, width=1, radius=4, shadow=False):
    lines = [f'[sub_resource type="StyleBoxFlat" id="{id}"]', f'bg_color = {color(bg)}']
    for edge in ['left','top','right','bottom']:
        lines += [f'border_width_{edge} = {width}', f'content_margin_{edge} = 12.0']
    lines += [f'border_color = {color(border)}']
    for corner in ['top_left','top_right','bottom_left','bottom_right']:
        lines.append(f'corner_radius_{corner} = {radius}')
    lines.append('corner_detail = 1')
    if shadow:
        lines += ['shadow_color = Color(0, 0, 0, 0.35)', 'shadow_size = 7', 'shadow_offset = Vector2(0, 5)']
    return '\n'.join(lines)+'\n\n'

theme = '[gd_resource type="Theme" load_steps=10 format=3]\n\n'
theme += '[ext_resource type="FontFile" path="res://assets/fonts/NotoSerifSC.ttf" id="1_font"]\n\n'
theme += '[sub_resource type="FontVariation" id="body_font"]\nbase_font = ExtResource("1_font")\nvariation_opentype = {"wght": 550.0}\n\n'
theme += '[sub_resource type="FontVariation" id="title_font"]\nbase_font = ExtResource("1_font")\nvariation_opentype = {"wght": 750.0}\n\n'
theme += style('normal','302116','856039',1,5,True)
theme += style('hover','50381f','e4bb75',2,5,True)
theme += style('pressed','79522c','f3cc88',2,5)
theme += style('focus','00000000','f5cd85',2,5)
theme += style('disabled','372c24','64503b',1,5)
theme += style('tooltip','efdcba','987341',1,5,True)
theme += '[resource]\ndefault_font = SubResource("body_font")\ndefault_font_size = 20\n'
theme += 'Button/fonts/font = SubResource("title_font")\n'
theme += 'Label/colors/font_color = '+color('f2dfba')+'\n'
theme += 'Button/colors/font_color = '+color('eddbb9')+'\n'
theme += 'Button/colors/font_hover_color = '+color('fff1d6')+'\n'
theme += 'Button/colors/font_pressed_color = '+color('fff2d8')+'\n'
theme += 'Button/colors/font_focus_color = '+color('fff2d8')+'\n'
theme += 'Button/constants/h_separation = 18\nButton/font_sizes/font_size = 22\n'
for s in ['normal','hover','pressed','focus','disabled']:
    theme += f'Button/styles/{s} = SubResource("{s}")\n'
theme += 'TooltipPanel/styles/panel = SubResource("tooltip")\nTooltipLabel/colors/font_color = '+color('422d1e')+'\n'
(ROOT/'assets/western_theme.tres').write_text(theme)

icons = {
 'home': '<path d="m32 6 7 15 17 2-12 12 3 18-15-8-15 8 3-18L8 23l17-2Z"/><circle cx="32" cy="30" r="5"/>',
 'codex':'<path d="M32 15Q20 8 7 12v38q13-4 25 3 12-7 25-3V12q-13-4-25 3v38M14 23l11 2m-11 7 11 2m15-9 10-2m-10 11 10-2"/>',
 'shop':'<path d="M8 25h48l-5-14H13ZM12 31v23h40V31M25 54V39h14v15M8 25v5q6 7 12 0 6 7 12 0 6 7 12 0 6 7 12 0v-5"/>',
 'research':'<path d="M24 8h16M27 8v19L11 51q-2 5 4 5h34q6 0 4-5L37 27V8M20 40h24"/><circle cx="28" cy="47" r="2"/><circle cx="36" cy="34" r="2"/>',
 'menu':'<path d="M8 12h48L32 36ZM32 36v19m-12 0h24M15 20h34"/>',
 'reviews':'<path d="M10 12h44v32H29L16 54V44h-6Z"/><circle cx="22" cy="28" r="2"/><circle cx="32" cy="28" r="2"/><circle cx="42" cy="28" r="2"/>',
 'coin':'<circle cx="32" cy="32" r="23"/><circle cx="32" cy="32" r="17"/><path d="M38 22H28q-8 0-6 8 1 3 11 3t6 9q-2 3-16 0m9-25v31"/>',
 'clock':'<circle cx="32" cy="32" r="23"/><path d="M32 16v17l11 7M32 8v4m0 40v4M8 32h4m40 0h4"/>',
 'bottle':'<path d="M25 6h14v9H25Zm2 9v9L16 35v22h32V35L37 24v-9M18 39h28v12H18"/>',
 'sun':'<circle cx="32" cy="32" r="13"/><path d="M32 4v7m0 42v7M4 32h7m42 0h7M12 12l5 5m30 30 5 5m0-40-5 5M17 47l-5 5"/>',
 'arrow':'<path d="M12 32h40M38 18l14 14-14 14"/>',
 'check':'<path d="m13 33 13 13 26-28"/>',
 'shaker':'<path d="M23 8h18v9H23ZM20 17h24l5 8H15Zm-5 8h34l-5 31H20ZM23 32l2 17"/>',
}
(ROOT/'assets/icons').mkdir(exist_ok=True)
for name, paths in icons.items():
    (ROOT/f'assets/icons/{name}.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="none" stroke="#d8b579" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">{paths}</g></svg>')

class Scene:
    def __init__(self, script):
        self.resources = {
            'theme': ('Theme','res://assets/western_theme.tres'),
            'script': ('Script',script),
            'ornament': ('Script','res://scripts/ornament_panel.gd'),
        }
        self.styles = style('wood','261b14f5','8c633d',2,6,True)
        self.styles += style('paper','eddbb7','a9834c',3,6,True)
        self.styles += style('primary','a45a2d','e1b76a',2,5,True)
        self.styles += style('primary_hover','bd713a','ffe0a0',2,5,True)
        self.styles += style('primary_pressed','80421f','ddb270',2,5)
        self.styles += style('selected','654524','d5a65e',2,5,True)
        self.styles += style('small','35251bda','755235',1,4)
        for id,bg,border in [('compact','302116','856039'),('compact_hover','50381f','e4bb75'),('compact_pressed','79522c','f3cc88')]:
            self.styles += style(id,bg,border,1,4).replace('content_margin_top = 12.0','content_margin_top = 5.0').replace('content_margin_bottom = 12.0','content_margin_bottom = 5.0')
        self.nodes = []
    def ext(self, key, kind, path):
        self.resources[key]=(kind,path)
        return f'ExtResource("{key}")'
    def node(self,name,kind,parent=None,rect=None,props=None,groups=None,unique=False):
        decl=f'[node name="{name}" type="{kind}"'
        if parent is not None: decl+=f' parent="{parent}"'
        if groups: decl+=' groups=['+', '.join(q(x) for x in groups)+']'
        decl+=']\n'
        if unique: decl+='unique_name_in_owner = true\n'
        if rect is not None:
            x,y,w,h=rect
            decl+='layout_mode = 0\n'
            decl+=f'offset_left = {x}.0\noffset_top = {y}.0\noffset_right = {x+w}.0\noffset_bottom = {y+h}.0\n'
        if props:
            decl+=''.join(f'{key} = {value}\n' for key,value in props.items())
        self.nodes.append(decl+'\n')
        return name if parent in (None,'.') else parent+'/'+name
    def label(self,name,parent,rect,text,size=20,ink='f1dfbd',align=0,unique=False,wrap=False):
        props={'mouse_filter':'2','text':q(text),'theme_override_font_sizes/font_size':str(size),'theme_override_colors/font_color':color(ink),'vertical_alignment':'1','horizontal_alignment':str(align)}
        if wrap: props['autowrap_mode']='2'
        return self.node(name,'Label',parent,rect,props,unique=unique)
    def panel(self,name,parent,rect,paper=False,small=False):
        return self.node(name,'Panel',parent,rect,{'mouse_filter':'2','theme_override_styles/panel':f'SubResource("{"small" if small else "paper" if paper else "wood"}")','script':'ExtResource("ornament")','material_kind':'1' if paper else '0'})
    def icon(self,name,parent,rect,key):
        return self.node(name,'TextureRect',parent,rect,{'mouse_filter':'2','texture':self.ext('icon_'+key,'Texture2D',f'res://assets/icons/{key}.svg'),'expand_mode':'1','stretch_mode':'5'})
    def button(self,name,parent,rect,text,route=None,primary=False,unique=False,icon=None):
        props={'mouse_default_cursor_shape':'2','text':q(text)}
        if rect[3] < 50:
            props['theme_override_font_sizes/font_size']='16'
            for state,st in [('normal','compact'),('hover','compact_hover'),('pressed','compact_pressed')]:
                props['theme_override_styles/'+state]=f'SubResource("{st}")'
        if route: props['metadata/route']=q(route)
        if primary:
            props['theme_override_styles/normal']='SubResource("primary")'
            props['theme_override_styles/hover']='SubResource("primary_hover")'
            props['theme_override_styles/pressed']='SubResource("primary_pressed")'
        if icon:
            props['icon']=self.ext('icon_'+icon,'Texture2D',f'res://assets/icons/{icon}.svg')
            props['icon_alignment']='0'
            props['theme_override_constants/icon_max_width']='30'
            props['theme_override_constants/h_separation']='19'
        return self.node(name,'Button',parent,rect,props,['route_buttons'] if route else None,unique)
    def line(self,name,parent,rect,ink='ad89514d'):
        self.node(name,'ColorRect',parent,rect,{'mouse_filter':'2','color':color(ink)})
    def save(self,path):
        head=f'[gd_scene load_steps={len(self.resources)+8} format=3]\n\n'
        for key,(kind,p) in self.resources.items():
            head+=f'[ext_resource type="{kind}" path="{p}" id="{key}"]\n'
        (ROOT/path).write_text(head+'\n'+self.styles+''.join(self.nodes))

full={'layout_mode':'1','anchors_preset':'15','anchor_right':'1.0','anchor_bottom':'1.0','grow_horizontal':'2','grow_vertical':'2'}
s=Scene('res://scripts/home.gd')
s.node('Home','Control',props={**full,'theme':'ExtResource("theme")','script':'ExtResource("script")'})
s.node('Background','TextureRect','.',props={**full,'mouse_filter':'2','texture':s.ext('background','Texture2D','res://assets/art/saloon-empty-v2.png'),'expand_mode':'1','stretch_mode':'6','script':s.ext('day_night','Script','res://scripts/day_night_background.gd')})
stage=s.node('Stage','Control','.',(0,0,1600,900),{'mouse_filter':'2'},unique=True)
s.node('Atmosphere','Control',stage,(0,0,1600,900),{'mouse_filter':'2','script':s.ext('atmosphere','Script','res://scripts/atmosphere.gd')})
s.node('GuestLayer','Node2D',stage,props={'script':s.ext('guest_spawner','Script','res://scripts/guest_spawner.gd')},unique=True)
home=s.node('HomeContent','Control',stage,(0,0,1600,900),{'mouse_filter':'2'},unique=True)
top=s.panel('TopBar',home,(24,18,1552,92))
s.icon('Emblem',top,(22,18,53,53),'home')
s.line('BrandDivider',top,(91,20,1,52))
s.label('Title',top,(110,9,415,49),'致未归的客人',34)
s.label('EnglishTitle',top,(114,59,390,20),'T H E   W E S T E R N   S A L O O N',12,'c29a64')
for name,x,icon,kicker,value in [('Gold',640,'coin','账户结余','300'),('Reputation',840,'home','店铺评分','暂无评分'),('Day',1040,'sun','营业日','第 1 天'),('Time',1240,'clock','黄昏','18:00')]:
    s.line(name+'Divider',top,(x-17,23,1,46))
    if name == 'Time':
        s.node('TimeIcon','Control',top,(x,27,34,34),{'mouse_filter':'2','script':s.ext('clock_face','Script','res://scripts/clock_face.gd')})
    else:
        s.icon(name+'Icon',top,(x,29,30,30),icon)
    s.label(name+'Label',top,(x+43,14,142,24),kicker,14,'b49a78',unique=name=='Time')
    s.label(name+'Value',top,(x+43,40,146,34),value,24,unique=True)
s.button('SlotsButton',top,(1465,17,65,58),'','slots',unique=True,icon='slots')
s.nodes[-1]=s.nodes[-1].rstrip()+'\ntooltip_text = "老虎机 · 20 金币一次"\n\n'
rail=s.panel('Navigation',home,(24,132,192,710))
s.label('RailTitle',rail,(20,23,152,27),'S A L O O N',15,'bda076',1)
s.line('RailRule',rail,(29,66,134,1))
for i,(key,name) in enumerate([('home','酒馆'),('codex','图鉴'),('shop','商店'),('research','研发'),('menu','酒单'),('reviews','评价')]):
    b=s.button('HomeButton' if key=='home' else key.title()+'Button',rail,(14,85+i*83,164,67),name,None if key=='home' else key,unique=key=='home',icon=key)
    if key=='home':
        s.nodes[-1]+=''
        s.nodes[-1]=s.nodes[-1].rstrip()+'\ntheme_override_styles/normal = SubResource("selected")\n\n'
s.line('RailBottomRule',rail,(29,601,134,1))
s.label('RailMotto',rail,(23,615,146,48),'好酒，值得等待。',15,'bda076',1)
s.button('HelpButton',rail,(35,657,122,34),'操作指引','help')
s.label('SceneKicker',home,(250,142,460,31),'落 日 已 至  /  SUNSET HOURS',15,'eed3a0',unique=True)
s.label('SceneTitle',home,(248,175,900,51),'给远道而来的人，留一杯好酒。',30,'fff0d2',unique=True)
s.line('SceneRule',home,(250,238,64,2),'d2a55c')
# A generous bottom conversation panel aligns with the navigation rail.
# The compact right note restores guest context without the old full-height panel.
badge=s.panel('ShiftBadge',home,(1350,142,226,44),small=True)
s.label('ShiftStatus',badge,(12,4,202,35),'准备中 · 第一个夜晚',16,'e8cca0',1,True)
note=s.panel('GuestNote',home,(1242,208,334,352),True)
s.label('NoteKicker',note,(28,22,278,24),'来 客 手 记  /  GUEST NOTES',13,'916a3e')
s.label('NoteTitle',note,(26,53,282,48),'静候来客',32,'462f20',unique=True)
s.label('NoteRole',note,(28,106,278,26),'每位客人，都带着自己的故事',16,'916a3e',unique=True)
s.line('NoteDivider',note,(28,145,278,1),'a77d4666')
s.label('NoteBody',note,(28,163,278,91),'擦亮杯子，备好材料。\n推开店门，听听今晚的第一个故事。',19,'705237',unique=True,wrap=True)
s.label('OrderKicker',note,(28,273,278,23),'今 晚 想 喝',13,'916a3e',unique=True)
s.label('NoteOrder',note,(28,300,278,29),'等待客人点单',17,'553c28',unique=True)
dialogue=s.panel('GuestDialogue',home,(248,618,1328,224))
s.node('GuestPortrait','TextureRect',dialogue,(24,38,128,128),{'mouse_filter':'2','expand_mode':'1','stretch_mode':'5'},unique=True)
s.label('GuestName',dialogue,(180,23,196,42),'静候来客',28,'ffe5ad',unique=True)
s.label('GuestRole',dialogue,(390,33,450,27),'一把空椅子，一段还没开始的交谈',15,'bda076',unique=True)
s.button('TalkButton',dialogue,(858,27,124,39),'再聊一句',unique=True)
s.line('DialogueRule',dialogue,(180,77,802,1),'ad89514d')
s.label('GuestSpeech',dialogue,(180,92,802,72),'推开店门，迎接今晚的第一位客人。',24,'f6e4c4',unique=True,wrap=True)
s.label('GuestTags',dialogue,(181,181,802,27),'和客人慢慢聊聊。',18,'d8b471',unique=True)
s.line('ActionDivider',dialogue,(1013,28,1,168))
s.button('OpenButton',dialogue,(1033,49,275,60),'开始营业    →',primary=True,unique=True)
s.button('NextGuestButton',dialogue,(1033,134,275,46),'送客，迎接下一位',unique=True)
s.label('ActionCaption',dialogue,(1033,144,275,27),'今晚，从第一杯好酒开始',14,'bda076',1,True)
s.label('BottomStatus',home,(29,857,910,26),'准备营业  /  第一个夜晚，等一位远道而来的客人。',14,'d3b78f',0,True)
s.label('Version',home,(1110,857,463,26),'酒谱手记  ·  鼠标 / 触屏  ·  v0.9',13,'b9986d',2)
s.node('PageHost','Control',stage,(0,0,1600,900),{'mouse_filter':'2'},unique=True)
s.save('scenes/home.tscn')

p=Scene('res://scripts/entry_preview.gd')
p.node('EntryPreview','Control',rect=(0,0,1600,900),props={'theme':'ExtResource("theme")','script':'ExtResource("script")'})
p.node('Backdrop','ColorRect','.',(0,0,1600,900),{'color':color('100c09cf')},unique=True)
panel=p.panel('Page','.',(345,165,910,570),True)
# The panel catches pointer input so clicking its blank areas does not dismiss it.
p.nodes[-1]=p.nodes[-1].replace('mouse_filter = 2','mouse_filter = 0')
p.label('Eyebrow',panel,(42,26,700,29),'THE WESTERN SALOON  /  酒馆事务',15,'98703e')
p.label('PageTitle',panel,(40,70,745,58),'西部杂货铺',36,'452e1d',0,True)
p.label('PageSubtitle',panel,(42,137,800,36),'好酒，从备齐材料开始。',20,'755333',0,True)
p.button('CloseButton',panel,(817,25,58,54),'×',unique=True)
p.node('Tabs','HBoxContainer',panel,(42,197,826,54),{'theme_override_constants/separation':'9'},unique=True)
p.label('Description',panel,(47,276,814,132),'',21,'593f29',0,True,True)
p.line('Divider',panel,(44,429,822,1),'a67d4670')
p.label('PreviewLabel',panel,(45,446,470,27),'入口预览 · 完整功能将在后续接入',15,'98703e')
p.label('FeatureList',panel,(45,479,548,30),'',16,'755333',0,True)
p.button('ReturnButton',panel,(638,461,229,65),'返回酒馆    →',primary=True,unique=True)
p.save('scenes/entry_preview.tscn')

config=ROOT/'project.godot'
text=config.read_text()
if 'run/main_scene' not in text:
    text=text.replace('config/name="致未归的客人"','config/name="致未归的客人"\nrun/main_scene="res://scenes/home.tscn"')
if '[autoload]' not in text:
    text=text.replace('[display]', '[autoload]\n\nNavigation="*res://scripts/navigation.gd"\n\n[display]')
if 'window/size/viewport_width' not in text:
    text=text.replace('[display]','[display]\n\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=900\nwindow/size/window_width_override=1280\nwindow/size/window_height_override=720\nwindow/size/min_width=800\nwindow/size/min_height=450\nwindow/handheld/orientation=0')
if '[input_devices]' not in text:
    text += '\n[input_devices]\n\npointing/emulate_mouse_from_touch=true\n'
config.write_text(text)
(ROOT/'.gitignore').write_text('.godot/\n*.translation\n.DS_Store\nexports/\n')
(ROOT/'.gitattributes').write_text('* text=auto eol=lf\n*.png binary\n*.ttf binary\n')
print('Native home + entry preview scenes generated.')
