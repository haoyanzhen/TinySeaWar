extends RefCounted

const CUSTOM_SIZES := [
	{"label": "1v1 单舰对决", "count": 1, "cost": 12, "base": "level.prototype_1v1"},
	{"label": "3v3 小型舰队", "count": 3, "cost": 22, "base": "level.prototype_3v3"},
	{"label": "5v5 中型舰队", "count": 5, "cost": 34, "base": "level.prototype_5v5"},
	{"label": "11v11 大型舰队", "count": 11, "cost": 64, "base": "level.prototype_11v11"},
]
const MAP_OPTIONS := [
	{"label": "开阔海域", "level": "level.prototype_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "港湾入口", "level": "level.prototype_harbor_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "破碎环礁", "level": "level.prototype_broken_atoll_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "中央沙洲", "level": "level.prototype_central_sandbar_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "新月岛", "level": "level.prototype_crescent_bay_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "双岛长海峡", "level": "level.prototype_double_island_long_channel_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "双航道礁线", "level": "level.prototype_dual_channel_reef_line_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "细长群岛", "level": "level.prototype_long_archipelago_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "大岛偏置", "level": "level.prototype_offset_large_island_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "环岛泻湖", "level": "level.prototype_ring_lagoon_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "散岛群", "level": "level.prototype_scattered_islands_3v3", "sizes": [1, 3, 5, 11]},
]
const TUTORIALS := [
	["T-01", "航向与选择", "移动、连续航点、镜头与旗舰胜利目标"],
	["T-02", "主炮与弹药", "瞄准、HE/AP、射角、装填和装甲伤害"],
	["T-03", "技能窗口", "技能目标、冷却与自动交火边界"],
	["T-04", "重甲压制", "大口径压制、副武器自动能力与月光区"],
	["T-05", "隐蔽雷击", "侦查、隐蔽、雷击角度与脱离"],
	["T-06", "航母猎杀", "目标价值、护航与自动索敌"],
	["T-07", "侦查共享", "前出接触与舰队共享目标"],
	["T-08", "编队考核", "框选、集火、自动开关与旗舰保护"],
]
const IMPLEMENTED_TUTORIAL_LEVEL_IDS := {
	"T-01": "level.tutorial.t01",
	"T-02": "level.tutorial.t02",
	"T-03": "level.tutorial.t03",
	"T-04": "level.tutorial.t04",
	"T-05": "level.tutorial.t05",
	"T-06": "level.tutorial.t06",
	"T-07": "level.tutorial.t07",
	"T-08": "level.tutorial.t08",
}
const CHALLENGES := {
	"小型海战 · 3v3": [["S-01", "首轮接敌"], ["S-02", "侧翼雷线"], ["S-03", "航空诱饵"], ["S-04", "双向伏击"], ["S-05", "狼群门槛"]],
	"中型海战 · 5v5": [["M-01", "港湾扩编"], ["M-02", "泻湖护航"], ["M-03", "群岛雷击"], ["M-04", "风暴猎场"], ["M-05", "海峡封锁"]],
	"大型海战 · 11v11": [["L-01", "舰队展开"], ["L-02", "岛侧航空走廊"], ["L-03", "双航道巨炮"], ["L-04", "风暴群岛合围"], ["L-05", "雷夜环礁终局"]],
}
