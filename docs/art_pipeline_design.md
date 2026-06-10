# 角色美术后处理管线设计

## 1. 目标

将 AI 生成的角色美术汇总图，稳定转为可进入游戏绑定测试的单件透明资产和配置数据。

管线采用半自动方案：

```text
试产 sheet
-> 程序清背景、拆件、补 padding、生成配置
-> Codex 通过 Computer Use 做视觉确认
-> 程序生成/更新 QA 报告
-> 进入绑定和战斗场景测试
```

人工目检环节由 Codex 通过 Computer Use 执行，不依赖用户手动逐张检查。

## 2. 输入

### 2.1 资产契约

`docs/art_design.md` 的「单角色美术资产清单」是生成、后处理和验收的唯一契约。流水线不得以「源图中没有」作为忽略必需资产的理由。

每名角色的统一 UI 资产包包含：

- 半身立绘和技能 cut-in。
- 默认、认真、受击三个基础表情。
- 头像、小头像和 Q 版头像。
- 技能图标和 MVP 六类舰种图标。

全身立绘必须从已验收的角色设定稿输出到正式处理目录，不得只留在 `concept/` 中。

每个角色保留试产母版：

```text
assets/characters/{id}/concept/
assets/characters/{id}/ui/
assets/characters/{id}/battle/
assets/characters/{id}/vfx/
assets/characters/{id}/meta/
```

核心输入文件：

```text
{id}_ui_sheet.png
{id}_battle_asset_sheet.png
{id}_anim_keyframes_sheet.png
{id}_vfx_reference_sheet.png
{id}_trial_log.md
```

## 3. 配置

后续应把裁切、绑定和配置生成从脚本内置数据迁移到角色级配置：

```text
assets/characters/{id}/postprocess_plan.json
```

配置内容：

- 源 sheet 路径。
- crop box。
- 输出文件名。
- 资产类型和标签。
- pivot。
- 绑定点。
- 动画状态。
- VFX 用途。
- padding 和 edge-fix 策略。

## 4. 程序化步骤

程序应负责：

- 扫描角色目录。
- 清背景，优先使用边缘连通背景删除，避免误删白发、泡沫、浅色航迹等角色纹理。
- 按配置裁切 sheet。
- 将初始裁剪框视为目标提示，而不是最终边界；在源图 alpha 上查找与初始框相交的前景连通块，合并这些连通块的真实包围盒，再加安全边距得到最终裁剪框。
- 连通块分析可以忽略接近全透明的低 alpha 桥接像素，避免将相邻 UI 件误判为同一主体；该阈值只用于确定裁剪边界，不修改最终输出的原始 alpha 纹理。
- trim alpha。
- 根据 alpha 包围盒和 alpha 加权重心添加平衡透明 padding，使内容尽量位于子图中心。
- 输出 RGBA PNG。
- 生成 `postprocess_manifest.json`。
- 生成 `meta_bind_points.json`。
- 生成 `anim_config.json`。
- 生成 `vfx_config.json`。
- 按需生成 QA 预览页。
- 自动检查 RGBA、空 alpha、贴边、缺文件和 JSON 可解析性。
- 按单角色资产契约检查完整性；必需项缺失时将角色包标记为 `incomplete`，即使已有 PNG 都可读也不得通过交付。

## 5. Codex Computer Use 视觉确认

程序生成预览页后，Codex 使用 Computer Use 打开本地预览页并检查。

预览页要求：

- 每张拆件显示在棋盘、深色、浅色三种背景上。
- 每张卡片显示源文件路径。
- 按角色和资产类型分组。

Codex 视觉检查项：

- 是否存在矩形白底、灰底、棋盘底或黑底残留。
- 是否有白边、黑边或明显 halo。
- 是否误删白发、白帽、白制服、泡沫、气泡、浅色航迹或发光 VFX。
- 是否裁切过紧。
- 是否切掉角色、舰装、炮口、鱼雷、飞机、VFX 轨迹或 UI 边框。
- 是否保留足够透明 padding。
- 小尺寸下角色和舰种是否仍可读。

Codex 输出判断：

- `pass`：可进入绑定测试。
- `polish`：可进入绑定测试，但最终导入前需要美术精修。
- `blocker`：阻塞导入测试，需要重新裁切、修背景或重新生成。

## 6. 输出

正式后处理输出：

```text
assets/characters/{id}/processed/source_alpha/
assets/characters/{id}/processed/ui/
assets/characters/{id}/processed/battle/
assets/characters/{id}/processed/vfx/
assets/characters/{id}/processed/anim/
assets/characters/{id}/processed/config/
```

配置输出：

```text
{id}_postprocess_manifest.json
{id}_meta_bind_points.json
{id}_anim_config.json
{id}_vfx_config.json
```

批次 QA 输出建议：

```text
assets/characters/qa/edge_qa_preview.html
assets/characters/qa/edge_qa_report.md
```

预览页建议支持两种模式：

- 常规模式：使用相对路径引用图片，页面体积小，适合本地服务器或引擎工具中查看。
- 稳定 QA 模式：将 PNG 以 data URI 嵌入 HTML，避免浏览器 `file://` 路径加载失败；适合 Codex 使用 Computer Use 做视觉确认。批量角色较多时应按角色或资产类型分页，避免单页过大。

## 7. 后续工具化方向

建议将当前脚本拆成通用命令：

```bash
python3 tools/art_pipeline/postprocess_character.py enterprise_cv6
python3 tools/art_pipeline/postprocess_character.py enterprise_cv6 --preview
python3 tools/art_pipeline/build_edge_qa_preview.py
python3 tools/art_pipeline/check_processed_assets.py
python3 tools/art_pipeline/check_character_asset_contract.py
```

其中 `--preview` 或 `build_edge_qa_preview.py` 负责生成视觉检查页，Codex 使用 Computer Use 完成视觉确认后，再将结果写入 QA 报告。默认后处理应优先保持快路径，不自动生成大体积嵌入式预览页。
