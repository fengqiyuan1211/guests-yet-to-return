# 工作台音效来源

以下四项来源页均标注 Creative Commons 0（CC0-1.0）。使用作者公开提供的 HQ MP3 试听文件制作游戏内短音效；未使用需登录下载的原始 WAV。

| 游戏文件 | 原作品与作者 | 许可 |
| --- | --- | --- |
| `pour.wav` | [Water pouring into glass bowl 01 — Rudmer_Rotteveel](https://freesound.org/people/Rudmer_Rotteveel/sounds/700352/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `stir.wav` | [Water stirred in glass with metal spoon — Tom_Kaszuba](https://freesound.org/people/Tom_Kaszuba/sounds/657552/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `shake.wav` | [Cocktail Shaker.wav — KenRT](https://freesound.org/people/KenRT/sounds/319995/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `clink.wav` | [Stirring glass — ChrisGrundlingh](https://freesound.org/people/ChrisGrundlingh/sounds/765653/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |

获取日期：2026-10-02。剪辑、格式、淡入淡出和文件校验值见 `sources.json`。原始试听源用于制作工作台内倒酒、搅拌、摇和及取放勺子的声音；未将作者姓名用于背书。

播放走现有 SFX 总线，停止操作、打开其他页面、失焦或退出工作台时停止，音量遵循游戏设置。

## 轻压音效（2026-10-05）

`muddle.wav` 为项目合成的 0.23 秒单次湿润捣压音：复用上述 Tom_Kaszuba 的 CC0 水声，叠加程序合成的低频接触声与短促揉叶噪声，经过低通、起落包络与淡出处理。它不是实地录制薄荷的录音；参数与校验值见 `sources.json`。有效下压每个行程只触发一次，力度影响音量，轻微随机音高减少重复感；松手、切页或失焦时停止，使用现有 SFX 总线与音量设置。
