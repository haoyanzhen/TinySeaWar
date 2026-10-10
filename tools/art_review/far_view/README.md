# 全48角色56px战斗修订

用户已采用56px基准，正式战斗由 `FarShipUnitView` 加载全48角色独立body/rig。当前人工入口：`reports/art/20261009-far-view-all/review.html`，技术记录同目录`validation.md`。首次打开项目需先导入PNG。

```sh
uv run --locked python tools/art_review/far_view/prepare_full_roster.py
uv run --locked python tools/art_review/far_view/validate_full_roster.py
godot --headless --path . --editor --import
godot --headless --path . --script scripts/tests/far_battle_art_test.gd
godot --path . --script tools/art_review/far_view/render_full_roster.gd
uv run --locked python tools/art_review/far_view/build_full_review.py
python3 -m http.server 8840 --bind 127.0.0.1
# 浏览器 http://127.0.0.1:8840/reports/art/20261009-far-view-all/review.html
```

正式源可从角色battle目录复现裁切，无需ignored raw；生成过程非确定性，提示词、库存、修正记录与源审查已保存。这里只更新战斗部件，原包裁切证据与来源保留；新逐帧动画、完整旧包迁移及逐角色人工审美不属于自动通过结论。首次三样本试验记录如下（历史范围）：

# 最远视角美术试验

设计入口：[临时方案](../../../workorder/20261009-far-view-art-design.md)。
人工材料：`reports/art/20261009-far-view/review.html`（本机生成、受既有ignore控制）。
这是三角色候选，不是正式48角色替换，不会记录进度。

```sh
godot --path . --script tools/art_review/far_view/launch.gd
# 三样本3v3（厌战、雪风、企业）
godot --path . --script tools/art_review/far_view/launch.gd -- --sample
```

F6切换原版/候选；F7切换48/56/64逻辑像素。最远视角默认开启，其他键位沿用正式战斗。
技术测试、渲染、视频与网页构建命令见报告目录validation.md。素材由Codex内置ImageGen生成，prompts.json保留请求；重新生成不是确定性的。候选源未附带时须携带整个报告目录；不得把正式processed素材替换成报告中的未审候选。
