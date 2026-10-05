# 酒馆背景音乐

这些文件是已有授权录音的轻度编辑版，不是原创作曲或 AI 重新作曲。

| 游戏用途 | 文件 | 原作 / 作者 | 授权与来源 |
| --- | --- | --- | --- |
| 20:00–04:00 营业 | night-jazz.mp3 → night-laura-source.mp3 | Jazz Late Night Cozy Calm Relaxing Mellow / Denis-Pavlov-Music ＋ Laura / kaazoom | [爵士原曲](https://pixabay.com/music/traditional-jazz-jazz-late-night-cozy-calm-relaxing-mellow-463808/) · [Laura 原曲](https://pixabay.com/music/acoustic-group-laura-soft-acoustic-guitar-folk-instrumental-144408/) |
| 旧夜间版本，保留备用 | night-laura.ogg | Laura - Soft Acoustic Guitar Folk Instrumental / kaazoom | [Pixabay 曲目页](https://pixabay.com/music/acoustic-group-laura-soft-acoustic-guitar-folk-instrumental-144408/) |
| 白天轮换 | day-country-waltz.ogg | Country Waltz / JuliusH | [Pixabay 曲目页](https://pixabay.com/music/traditional-country-country-waltz-8065/) |
| 白天轮换 | day-richer.ogg | Richer / Alex McCulloch (Pro Sensory) | [CC0 / OpenGameArt](https://opengameart.org/content/richer) |

Pixabay 曲目遵守 [Pixabay Content License](https://pixabay.com/service/license-summary/)，允许免费使用、修改，不强制署名；不得作为独立音乐文件重新销售或分发。这里用于游戏配乐。原始文件不随工程打包。授权核对日期：2026-09-30。

编辑内容：夜间曲目在游戏内以 94% 速度播放，整体稍微放慢并轻微降低音高；两个播放器实现 3.5 秒交叉淡化，一首结束后自动切到另一首，形成“深夜爵士 → 西部木吉他”的串曲。白天曲目仍使用已处理的 OGG 版本。`credits.json` 保存来源和授权记录。

建议在发布版制作人员名单中保留原作与作者署名。新增曲目应继续放到 Music 总线；机械、点击等效果音使用 SFX 总线。

## 工作台音乐（2026-10-03）

"George Street Shuffle" Kevin MacLeod (incompetech.com).
Licensed under Creative Commons: By Attribution 4.0 License.
https://creativecommons.org/licenses/by/4.0/

来源：https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300035
文件：`workbench-george-street.mp3`，原始录音，未剪辑。游戏设置的声音区域提供署名及来源链接。
进入工作台后以现有双音轨交叉淡化 3.5 秒切换；退出恢复大厅曲目。音量沿用 Music 总线。


商店：Carpe Diem；研发：Bossa Antigua。两曲均为 Kevin MacLeod (incompetech.com)，CC BY 4.0，原始录音未剪辑。出处、许可链接及 SHA-256 见 credits.json；游戏设置页提供署名。与大厅、工作台共用 Music 音量及 3.5 秒渐变。

2026-10-05 商店试听调整：Carpe Diem 以木管、尤克里里、吉他、木琴和轻打击乐构成明亮的港口市集方向，原速 96 BPM，保持原调。替换此前 Local Forecast - Elevator，不再使用该曲作为商店 BGM。
