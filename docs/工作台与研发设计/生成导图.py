from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import html
import xml.etree.ElementTree as ET

OUT = Path(__file__).resolve().parent
FONT = OUT.parents[1] / 'assets/fonts/NotoSerifSC.ttf'
W,H=2800,2000
BG='#F7F2E8'; INK='#3D342B'; MUTED='#786C5D'; LINE='#B9A68B'
im=Image.new('RGB',(W,H),BG); draw=ImageDraw.Draw(im)
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',f'<rect width="{W}" height="{H}" fill="{BG}"/>']
fonts={}
def font(n):
    if n not in fonts: fonts[n]=ImageFont.truetype(str(FONT),n)
    return fonts[n]
def text(x,y,s,n=32,c=INK):
    draw.text((x,y),s,font=font(n),fill=c,anchor='lt')
    svg.append(f'<text x="{x}" y="{y+n*.86}" font-family="Noto Serif SC, Songti SC, serif" font-size="{n}" fill="{c}">{html.escape(s)}</text>')
def box(x,y,w,h,fill,stroke=None,r=22):
    draw.rounded_rectangle((x,y,x+w,y+h),radius=r,fill=fill,outline=stroke,width=2)
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke or fill}" stroke-width="2"/>')
def line(points,c=LINE,w=4):
    draw.line(points,fill=c,width=w,joint='curve')
    svg.append(f'<polyline points="'+ ' '.join(f'{x},{y}' for x,y in points)+f'" fill="none" stroke="{c}" stroke-width="{w}"/>')

groups=[
('01','职责与体验',[
('已确认','第一人称调酒；暖色手绘、西部与海港'),
('已确认','真实原料、剂量、冰型与技法；不做液体物理'),
('已确认','工作台负责制作；研发负责试调与保存'),
('已确认','Last Word 故事首杯；A2 仅为技术样例'),
('建议','一套制作核心，由模式决定结果去向')]),
('02','页面与操作',[
('已确认','左上订单纸条：要求、材料、步骤'),
('已确认','选杯 → 取料量取 → 加入 → 选冰'),
('已确认','轻压／摇和／搅拌 → 过滤 → 装饰 → 出杯'),
('已确认','允许偏离酒谱；以后扩展多倒少倒与融水'),
('建议','中央容器、侧边材料、底部操作；目标与实际并列')]),
('03','两种模式',[
('已确认','营业：关联顾客订单，交付后评价与销售结算'),
('已确认','研发：改编／新建 → 共用工作台 → 结果'),
('已确认','双语命名 → 保存 DIY → 自行决定是否上架'),
('已确认','传说特调由配方道具解锁，与 DIY 分开'),
('待定','灵感、次数、保存数量、允许修改范围')]),
('04','生命周期',[
('建议','准备 → 制作 → 冻结结果 → 交付／保存'),
('已确认','切页保留半成品；取消、失败、重做不自动退料'),
('建议','重做创建新会话；教学使用独立虚拟资源'),
('建议','歇业保留半成品，失效订单不得向新客人交付'),
('建议','恢复同一快照；失败重试沿用原请求编号')]),
('05','数据与配方版本',[
('已确认','标准酒谱 ≠ 实际单杯；目标属性 ≠ 实际属性'),
('建议','配方草稿 → 玩家确认 → 已保存配方版本'),
('已确认','本杯锁定版本；官方不可覆盖；另存与修订分开'),
('已确认','四维暂用 0—100；酒感 ≠ ABV'),
('已确认','风味、口感、禁忌、剧情标签、Buff 分开')]),
('06','物料与可靠性',[
('建议','库存 → 会话扣一次；容器之间转移不再扣'),
('已确认','取 18 ml、漏 1 ml：留存 17 ml，成本算 18 ml'),
('建议','库存、容器、动作和凭据一次提交；请求可去重'),
('已确认','保存可复现做法，不把偶然洒漏写成标准步骤'),
('待定','评分系数、融水模型、费用、Buff；不代填数值')]),
('07','接口与 Godot 结构',[
('建议','场景：研发准备／共用工作台／结果／保存'),
('建议','服务：会话、配方、研发、计算、存档与交付'),
('建议','库存管物料；图鉴管展示；订单与钱包管结算'),
('建议','DIY 保存只进图鉴；酒单上架由玩家确认'),
('现状','研发／制作仍为入口；现有送客回调不负责收款')]),
('08','开发与验收',[
('建议','对齐数据接口 → 制作核心与存档 → 研发闭环'),
('建议','DIY 版本与图鉴 → 营业结算 → 正式内容联调'),
('建议','首版单会话、离散计量；连续倾倒与多杯后续做'),
('建议','验收：守恒、去重、中断恢复、版本隔离、一次收款'),
('待定','归航／homeward 与回响／ECHO WORD 对应关系')])]
colors={'已确认':'#3E7065','建议':'#476B8B','待定':'#A46D29','现状':'#786078'}
text(80,64,'致未归的客人',38,MUTED)
text(80,124,'工作台与研发 · 开发思维导图',64)
text(80,214,'设计 v0.1  /  2026.09.30  /  配套说明文档提供字段、事务流程与任务验收表',27,MUTED)
# Four rows, two sides around one shared centre.
ys=[310,710,1110,1510]
for side in (0,1):
    for y in ys:
        if side==0: line([(1210,1050),(1170,1050),(1170,y+170),(1130,y+170)])
        else: line([(1590,1050),(1630,1050),(1630,y+170),(1670,y+170)])
for idx,(num,title,items) in enumerate(groups):
    x=80 if idx<4 else 1670; y=ys[idx%4]
    box(x,y,1050,340,'#FFFCF6','#D7C8B0')
    text(x+28,y+22,num,31,MUTED)
    text(x+96,y+19,title,42)
    for j,(status,body) in enumerate(items):
        ty=y+92+j*47
        box(x+26,ty,100,34,colors[status],r=8)
        text(x+35,ty+4,status,23,'#FFFFFF')
        assert draw.textlength(body,font=font(29))<885, body
        text(x+145,ty+2,body,29)
box(1210,940,380,220,'#563E2C',r=26)
text(1255,981,'一套制作系统',39,'#FFF6E8')
text(1258,1048,'营业  /  研发',37,'#EBD5AF')
text(1260,1100,'记录每一杯的实际过程',22,'#EBD5AF')
text(80,1906,'阅读标记：已确认＝保留需求   建议＝新增方案   待定＝尚未定稿   现状＝仓库检查结果',30,MUTED)
text(80,1955,'范围：仅设计文档与导图，不改游戏代码。表格未核验；不将酒单示例视为正式配方。',25,MUTED)
im.save(OUT/'工作台与研发-开发思维导图.png')
svg.append('</svg>')
(OUT/'工作台与研发-开发思维导图.svg').write_text('\n'.join(svg),encoding='utf-8')
lines=['# 工作台与研发 · 可编辑大纲','', '2026-09-30 · 设计 v0.1。与导图主分支对应；细节以开发说明为准。','', '- 工作台与研发：一套制作系统，两种使用模式']
root=ET.Element('opml',version='2.0'); head=ET.SubElement(root,'head'); ET.SubElement(head,'title').text='工作台与研发开发大纲 v0.1'
body=ET.SubElement(root,'body'); parent=ET.SubElement(body,'outline',text='工作台与研发：一套制作系统，两种使用模式')
for num,title,items in groups:
    lines.append(f'  - {num} {title}')
    node=ET.SubElement(parent,'outline',text=f'{num} {title}')
    for status,txt in items:
        s=f'【{status}】{txt}'
        lines.append('    - '+s)
        ET.SubElement(node,'outline',text=s)
lines += ['', '## 补充任务大纲（建议）','', '- 数据与接口对齐', '  - 核对故事首杯和名称对应；取得 A2 原表后再录入', '  - 确定原料单位、容器容量、来源版本与成本快照', '  - 对齐库存、图鉴、订单、钱包和存档权威归属', '- 制作核心', '  - 创建会话和锁定目标版本', '  - 取料、转移、损耗与非液体单位处理', '  - 冰、技法、过滤、装饰及冻结单杯', '  - 命令去重、事务快照、中断恢复和重做', '- 研发闭环', '  - 基础配方／空白 DIY 准备页', '  - 结果分析与可复现草稿', '  - 双语命名、备注、另存与修订', '  - 图鉴 DIY 分类、详情和以此研发', '  - 配额、消耗与修改范围配置；未配置不猜值', '- 营业联调', '  - 订单与接待绑定、硬性禁忌与评价分项', '  - 交付意图、一次收款、完成后通知主页', '  - 04:00 歇业与失效订单处理', '- 核心验收', '  - 18 ml 取出／1 ml 洒漏／17 ml 留存', '  - 切页与重启后库存、容器、动作一致', '  - 保存与交付重试不重复扣费、不重复收款', '  - 官方与 DIY 隔离、旧杯固定版本、不自动上架']
(OUT/'工作台与研发-可编辑大纲.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
# Include the supplementary task tree in OPML as well.
stack=[(0,parent)]
for ln in lines[lines.index('## 补充任务大纲（建议）')+2:]:
    if not ln.strip(): continue
    indent=len(ln)-len(ln.lstrip())
    if indent==0:
        node=ET.SubElement(parent,'outline',text='【建议任务】'+ln[2:])
    else:
        ET.SubElement(node,'outline',text=ln.strip()[2:])
ET.indent(root)
ET.ElementTree(root).write(OUT/'工作台与研发-可编辑大纲.opml',encoding='utf-8',xml_declaration=True)
# Smaller review image for visual QA; full-resolution deliverable stays intact.
im.resize((1400,1000)).save(OUT/'导图预览.png')
print('Generated PNG 2800×2000, SVG, Markdown outline and OPML.')
