#!/usr/bin/env python3
"""Summarize the manually designated 20-seed damage/dispersion balance run."""

from __future__ import annotations

import csv
import json
import statistics
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "artifacts/simulations/sim.balance.damage_ttk_20"


def mean(rows, key):
    values = [float(row.get(key, 0.0)) for row in rows]
    return statistics.fmean(values) if values else 0.0


def percentile(values, ratio):
    if not values:
        return 0.0
    values = sorted(values)
    position = ratio * (len(values) - 1)
    lower = int(position)
    upper = min(len(values) - 1, lower + 1)
    return values[lower] + (values[upper] - values[lower]) * (position - lower)


def write_csv(rows):
    fields = [
        "seed", "end_state", "finish_reason", "duration_seconds", "ttk_seconds",
        "first_flagship_sink_seconds", "gun_resolutions", "geometry_intersections",
        "geometry_misses", "unknown_geometry", "hit_roll_successes", "hit_roll_failures",
        "effective_damage", "raw_damage", "final_damage", "damage_events", "main_gun_damage",
        "secondary_gun_damage", "geometry_intersection_rate", "actual_hit_rate",
    ]
    with (OUTPUT / "summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows({field: row.get(field, "") for field in fields} for row in rows)


def make_chart(rows, summary):
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return False

    classified = sum(int(row.get("gun_resolutions", 0)) - int(row.get("unknown_geometry", 0)) for row in rows)
    intersections = sum(int(row.get("geometry_intersections", 0)) for row in rows)
    actual_hits = intersections + sum(int(row.get("hit_roll_successes", 0)) for row in rows)
    damage_events = sum(int(row.get("damage_events", 0)) for row in rows)
    ttk = [float(row.get("ttk_seconds", 0.0)) for row in rows if row.get("end_state") == "Finished"]

    fig, axes = plt.subplots(1, 2, figsize=(12, 5), constrained_layout=True)
    axes[0].bar(
        ["Gun resolutions", "Geometry hit", "Actual hit", "Damage events"],
        [classified, intersections, actual_hits, damage_events],
        color=["#58708a", "#3f8f9f", "#d18b3d", "#6a9b62"],
    )
    axes[0].set_title("Gun pipeline (20 fixed-seed runs)")
    axes[0].set_ylabel("Events")
    axes[0].grid(axis="y", color="#d9dee5", linewidth=0.7)
    axes[0].set_axisbelow(True)

    axes[1].plot(range(1, len(ttk) + 1), ttk, marker="o", color="#58708a", linewidth=1.8)
    axes[1].axhline(statistics.fmean(ttk) if ttk else 0.0, color="#d18b3d", linestyle="--", linewidth=1.4, label="平均 TTK")
    axes[1].set_title("TTK by fixed seed")
    axes[1].set_xlabel("Completed run")
    axes[1].set_ylabel("Seconds")
    axes[1].grid(color="#d9dee5", linewidth=0.7)
    axes[1].set_axisbelow(True)
    axes[1].legend(frameon=False, labels=["Mean TTK"])
    fig.suptitle("0.25 Damage Multiplier and Gun Dispersion", fontsize=14)
    fig.savefig(OUTPUT / "damage_ttk_pipeline.png", dpi=160, facecolor="white")
    plt.close(fig)
    return True


def write_report(metadata, rows, chart_written):
    finished = [row for row in rows if row.get("end_state") == "Finished"]
    classified = sum(int(row.get("gun_resolutions", 0)) - int(row.get("unknown_geometry", 0)) for row in rows)
    intersections = sum(int(row.get("geometry_intersections", 0)) for row in rows)
    actual_hits = intersections + sum(int(row.get("hit_roll_successes", 0)) for row in rows)
    damage_events = sum(int(row.get("damage_events", 0)) for row in rows)
    ttk = [float(row.get("ttk_seconds", 0.0)) for row in finished]
    geometry_rate = intersections / classified if classified else 0.0
    actual_hit_rate = actual_hits / classified if classified else 0.0
    damage_rate = damage_events / classified if classified else 0.0
    lines = [
        "# 伤害倍率与舰炮散布平衡测试",
        "",
        "本实验由人工明确指定为大版本平衡验证，运行 20 个固定种子；不代表普通单项改动的默认验收规模。",
        "",
        f"- 场景：`{metadata.get('level_definition_id', '')}`，双方 `LatestRuntimeAI`，标准 Profile",
        f"- 伤害倍率：`{float(metadata.get('damage_multiplier', 0.0)):.2f}`",
        f"- 固定种子：`{metadata.get('seed_count', 0)}` 个",
        f"- 正常结束：`{len(finished)}/{len(rows)}`",
        "",
        "## 汇总结果",
        "",
        "| 指标 | 结果 |",
        "| --- | ---: |",
        f"| 舰炮结算事件（已分类） | {classified} |",
        f"| 几何相交事件 | {intersections}（{geometry_rate * 100:.2f}%） |",
        f"| 实际命中事件 | {actual_hits}（{actual_hit_rate * 100:.2f}%） |",
        f"| 产生有效伤害事件 | {damage_events}（{damage_rate * 100:.2f}%） |",
        f"| 平均有效伤害/局 | {mean(rows, 'effective_damage'):.2f} |",
        f"| 中位有效伤害/局 | {statistics.median(float(row.get('effective_damage', 0.0)) for row in rows):.2f} |",
        f"| 平均 TTK | {statistics.fmean(ttk) if ttk else 0.0:.2f}s |",
        f"| TTK P10 / P90 | {percentile(ttk, 0.1):.2f}s / {percentile(ttk, 0.9):.2f}s |",
        "",
        "## 解释口径",
        "",
        "- 几何相交来自 `AttackResolved.geometry_intersection=true`，代表炮弹落点进入舰体椭圆的有效范围。",
        "- `NO_TARGET_IN_AREA` 计为几何未相交；其他命中原因单列为未知，避免把未拆解事件强行归类。",
        "- 实际命中包含几何相交后的碰撞命中与命中率随机抽样成功；有效伤害使用公共伤害结算的 `final_damage`。",
        "- TTK 使用战斗结束时长；由于 3v3 的主要结束条件是旗舰击沉，它代表本局达到胜负条件的时间。",
        "",
        f"图表：`damage_ttk_pipeline.png`（已生成：{'是' if chart_written else '否，环境缺少 matplotlib'}）",
        "数据表：`summary.csv`；逐局原始数据：`runs.jsonl`。",
    ]
    (OUTPUT / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    payload = json.loads((OUTPUT / "summary.json").read_text(encoding="utf-8"))
    metadata = payload["metadata"]
    rows = payload["runs"]
    write_csv(rows)
    chart_written = make_chart(rows, metadata)
    write_report(metadata, rows, chart_written)


if __name__ == "__main__":
    main()
