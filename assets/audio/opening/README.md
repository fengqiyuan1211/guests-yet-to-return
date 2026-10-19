海浪底噪由项目程序生成：固定随机种子 161026，频域滤波噪声与周期潮汐包络，24 秒无缝循环，22050 Hz 单声道 PCM16。不是实地录音。标题界面低音量叠加在 Laura 配乐下，受音效滑块控制。

button-shimmer.wav 为项目原创合成的轻柔星光音，使用 tools/build_title_chime.py 生成，无外部采样。44100 Hz、单声道 PCM16、1.05 秒；缓慢柔化起音，以很弱的五度、八度泛音延迟闪现，移除敲击感和不谐和的金属泛音。相较第一版，素材峰值与播放增益合计降低约 8.3 dB。仅用于开始界面按钮的鼠标进入反馈，受总音量与音效音量控制；260 毫秒防连触、最多两个尾音重叠，禁用按钮不响，切出窗口停止。

2026-10-17 序章声音：

- `quiet-room.wav`：原创合成的稀疏键盘音乐，40 秒，22050 Hz 单声道 PCM16。使用 Am(add9)、Fmaj7、Cmaj7、Gsus2，柔化起音和自然衰减，没有外部采样。由 `tools/build_opening_audio.py` 生成，交由现有 Music 双播放器进行 3.5 秒交叉淡化。
- `mail-arrival.wav`：同一工具生成的原创柔和双音提示，0.85 秒；只在邮件抵达节点播放，不因查看历史重复播放。
- `chuckle.wav`：jodybruchon 的 “Voices - male laughter - mild chuckles.wav”，CC0。来源：https://freesound.org/people/jodybruchon/sounds/459455/ 。公开 HQ 预览解码后做音量和淡入淡出处理；明细见 `story-sources.json`。
- 碰杯复用 `assets/audio/workbench/clink.wav`；纸箱摩擦复用 `assets/audio/interface/foley/leaf-1.wav`，作为柔和干燥摩擦拟音。授权分别见原目录 sources 文件。
- 办公室旧日复用 Bossa Antigua，城市酒吧复用夜间爵士，海路与抵岛复用 Laura；授权信息见 `assets/audio/music/credits.json`。
