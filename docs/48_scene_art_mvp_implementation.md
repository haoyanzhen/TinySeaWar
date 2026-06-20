# 场景美术 MVP 实现记录

## 1. 当前范围

本轮仅实现纯环境场景，不包含航迹、炮击、鱼雷、航空、防空、潜艇、沉没、范围圈、选中框或画外战斗警告。

已实现内容：

- 1920 x 1080 逻辑基准和 4K 物理输出。
- 固定正俯视、不可旋转镜头。
- 玩家位于地图下部、敌方位于地图上部的部署方向。
- 4096 x 2304 开阔海域地图，宽高均超过可见区域两倍。
- 开局镜头以玩家初始编队中心为中心并保持手动模式。
- `WASD` 镜头移动。
- `F` 跟随当前选中的己方舰船，再次按下退出跟随。
- 晴昼、多云、暮色三套海况参数，可通过 `7`、`8`、`9` 切换。
- 程序化水体明暗、窄波纹、稀疏闪光、云影、暮色反光和地图边缘压暗。
- 暂停时海面环境动画暂停。
- 镜头边界限制，任何分辨率下都不会露出地图外空白。

## 2. AI 场景资产

使用内置图像生成工作流制作三张固定正俯视海域风格锚点：

```text
assets/environments/ocean/concept/ocean_style_day_clear.png
assets/environments/ocean/concept/ocean_style_cloudy.png
assets/environments/ocean/concept/ocean_style_dusk.png
```

共同约束：

- 16:9 正俯视开放海域。
- 无地平线、岛屿、舰船、角色、UI 和文字。
- 低视觉噪声，适合作为 2D 战斗背景。
- 分别表现晴昼青蓝、多云蓝灰和暮色暖反光。

从锚点程序化制作的纹理候选：

```text
assets/environments/ocean/common/ocean_base_day_clear_tile.png
assets/environments/ocean/common/ocean_base_cloudy_tile.png
assets/environments/ocean/common/ocean_base_dusk_tile.png
assets/environments/ocean/common/ocean_cloud_shadow_tile.png
assets/environments/ocean/common/ocean_wave_highlight_tile.png
```

这些纹理保留为后续迭代源文件。当前运行时不直接混入 AI 平铺底图，避免大地图出现可识别的重复纹样。

## 3. 程序实现

### 3.1 海面

`ocean_surface.gdshader` 使用 Godot 4 `canvas_item` Shader，兼容项目当前的 Compatibility 渲染器。

运行时海面由以下部分合成：

```text
深浅海色
+ 双方向低频水体变化
+ 噪声扰动的窄波峰
+ 稀疏交叉闪光
+ 缓慢移动的宽云影
+ 暮色暖色反光
+ 屏幕边缘轻微压暗
+ 地图边缘自然压暗
```

动画时间由脚本传入，不直接依赖 Shader 的 `TIME`，因此战斗暂停时环境动画能够同步暂停。

### 3.2 海况配置

海况参数保存在：

```text
data/environments/ocean_palettes.json
```

当前配置：

- `day_clear`：明亮青蓝，较清晰的波纹和高光。
- `cloudy`：深蓝灰，较强云影和较低闪光。
- `dusk`：蓝灰暮色，低亮波纹和暖色反射。

关卡通过 `map.ocean_palette` 选择默认海况。

### 3.3 地图与镜头

原型关卡地图统一调整为 4096 x 2304：

- 玩家舰队出生在地图下部并朝上。
- 敌方舰队出生在地图上部并朝下。
- 镜头初始位置取玩家存活舰船的位置平均值。
- 手动输入会退出舰船跟随模式。
- 跟随目标沉没或失效时自动返回手动模式。
- 镜头根据当前逻辑视口尺寸动态限制移动范围。

## 4. 主要文件

```text
project.godot
scenes/battle/prototype_battle.tscn
scripts/presentation/battle/prototype_battle.gd
scripts/presentation/battle/ocean_surface.gd
scripts/presentation/battle/battle_hud.gd
assets/environments/ocean/common/ocean_surface.gdshader
data/environments/ocean_palettes.json
data/levels/prototype_levels.json
scripts/tests/scene_presentation_test.gd
scripts/tests/render_scene_qa.gd
```

## 5. 验收结果

自动测试：

- 战斗领域测试：27 项通过。
- 场景显示测试：11 项通过。
- 主场景在 Godot 4.6.3 Compatibility 渲染器下启动无错误。

实际渲染验证：

| 输出 | 结果 |
| --- | --- |
| 1920 x 1080 | 通过 |
| 2560 x 1440 | 通过 |
| 3840 x 2160 | 通过 |
| 镜头移动至地图其他区域 | 无空白、海面连续 |
| 镜头移动至地图边缘 | 不越界，边缘自然压暗 |
| 三套海况切换 | 颜色、云影、波纹和暮色反光正确切换 |

QA 渲染工具示例：

```bash
godot --path . --script scripts/tests/render_scene_qa.gd -- \
  --size=3840x2160 \
  --output=/tmp/tinyseawar_scene_4k.png \
  --palette=dusk \
  --camera=2048,1720
```

## 6. 后续纯场景优化

以下内容不阻塞当前 MVP：

- 使用独立美术工具进一步制作更自然的无缝纹理。
- 增加小雨和低雾环境变体。
- 为低、中、高画质档提供不同环境采样数量。
- 在正式角色资产接入后重新校准海面明度和波纹对比度。
