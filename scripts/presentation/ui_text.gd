extends RefCounted

const OCEAN_PALETTE_PATH := "res://data/environments/ocean_palettes.json"


static func mode_name(level_id: String) -> String:
	match level_id:
		"level.prototype_1v1": return "1v1 单舰对决"
		"level.prototype_3v3": return "3v3 小队演习"
		"level.prototype_5v5": return "5v5 舰队战"
		"level.prototype_11v11": return "11v11 大规模会战"
		"level.prototype_harbor_3v3": return "3v3 港湾入口"
		_: return "未知模式"


static func phase_name(phase: String) -> String:
	match phase:
		"Running": return "战斗中"
		"Paused": return "已暂停"
		"Finished": return "战斗结束"
		"Setup": return "准备中"
		_: return "状态未知"


static func camera_mode_name(mode: String) -> String:
	return "跟随" if mode == "Follow" else "自由观察"


static func operation_mode_name(mode: String) -> String:
	match mode:
		"AIMING_PRIMARY": return "主武器瞄准"
		"TARGETING_SKILL": return "技能选目标"
		"PLACING_ROUTE": return "连续布置路径"
		_: return "常规操作"


static func palette_name(palette_id: String) -> String:
	var file := FileAccess.open(OCEAN_PALETTE_PATH, FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("palettes")) == TYPE_DICTIONARY:
			var palette: Dictionary = parsed["palettes"].get(palette_id, {})
			if not palette.is_empty():
				return str(palette.get("display_name", palette_id))
	return "未知海域"


static func ship_class_name(ship_class: String) -> String:
	match ship_class:
		"Battleship": return "战列舰"
		"HeavyCruiser": return "重巡洋舰"
		"LightCruiser": return "轻巡洋舰"
		"Destroyer": return "驱逐舰"
		"Submarine": return "潜艇"
		"Carrier": return "航空母舰"
		_: return "未知舰种"


static func target_type_name(target_type: String) -> String:
	match target_type:
		"Self": return "自身"
		"Enemy", "Entity": return "敌方单位"
		"Area", "Position": return "指定区域"
		_: return "未知目标"


static func faction_name(faction_id: String) -> String:
	match faction_id:
		"player": return "己方"
		"enemy": return "敌方"
		_: return "未知阵营"


static func result_reason_name(reason: String) -> String:
	match reason:
		"FLAGSHIP_SUNK": return "旗舰沉没"
		"FLAGSHIP_SUNK_SIMULTANEOUS": return "双方旗舰同时沉没"
		"TIME_LIMIT": return "战斗时间耗尽"
		_: return "战斗结束"


static func reason_name(reason_code: String) -> String:
	match reason_code:
		"OK": return "可以执行"
		"BATTLE_NOT_RUNNING": return "战斗尚未进行"
		"BATTLE_NOT_PAUSED": return "战斗未暂停"
		"UNIT_NOT_FOUND": return "未找到单位"
		"UNIT_NOT_CONTROLLABLE": return "该单位不可控制"
		"UNIT_SUNK": return "单位已沉没"
		"MOVEMENT_ASSIST_DISABLED": return "自动航行已关闭"
		"AUTO_FIRE_DISABLED": return "主要武器自动开火已关闭或暂停"
		"PRIMARY_WEAPON_UNAVAILABLE": return "没有可用的主要武器"
		"WEAPON_RELOADING": return "武器装填中"
		"TORPEDO_MOUNT_INTERVAL": return "鱼雷管组切换中"
		"TARGET_TOO_CLOSE": return "目标距离过近"
		"TARGET_OUT_OF_RANGE": return "目标超出射程"
		"MINE_AREA_CONTAINS_ENEMY": return "区域内已有敌方单位"
		"MINE_DEPLOYMENT_UNAVAILABLE": return "布雷任务暂不可用"
		"TARGET_NOT_VISIBLE": return "目标尚未发现"
		"FIRE_ARC_INVALID": return "目标不在射界内"
		"INVALID_TARGET", "INVALID_TARGET_TYPE": return "目标无效"
		"AMMO_SWITCH_DISABLED": return "无法切换弹药"
		"SKILL_NOT_FOUND": return "未找到技能"
		"SKILL_ON_COOLDOWN": return "技能冷却中"
		"TARGET_POSITION_ON_LAND": return "目标位置在陆地或岸线上"
		"NO_NAVIGATION_PATH": return "当前舰体无法到达目标"
		"TERRAIN_BLOCKS_MOVEMENT": return "航路被地形阻挡"
		"TERRAIN_BLOCKS_SHELL_PATH": return "炮弹路径被岛岸阻挡"
		"TERRAIN_BLOCKS_LINE_OF_SIGHT": return "视线被岛岸阻挡"
		"WATER_DEPTH_NOT_ALLOWED": return "当前舰体不能进入该水深"
		"TIDE_ACCESS_RESTRICTED": return "潮位暂时封闭该浅水通道"
		"FACILITY_INTERACTION_NOT_ALLOWED": return "当前不能操作该设施"
		"FACILITY_NOT_ACTIVE": return "设施尚未启用"
		"FACILITY_SUPPRESSED": return "设施处于压制状态"
		"FACILITY_OUT_OF_RANGE": return "尚未进入设施交互水域"
		"SUPPORT_MISSION_UNAVAILABLE": return "支援任务当前不可用"
		"AVIATION_WEATHER_BLOCKED": return "当前海况不允许航空任务"
		"INVALID_COMMAND_STRUCTURE", "UNKNOWN_COMMAND": return "无法识别该操作"
		_: return "操作无法执行"


static func ammo_name(ammo_type: String) -> String:
	match ammo_type:
		"HE": return "高爆弹"
		"AP": return "穿甲弹"
		_: return "无弹种"


static func character_name(character_id: String) -> String:
	match character_id.trim_prefix("ship."):
		"enterprise_cv6": return "企业号"
		"iowa": return "衣阿华号"
		"san_diego": return "圣地亚哥号"
		"ward": return "沃德号"
		"warspite": return "厌战号"
		"hood": return "胡德号"
		"sirius": return "天狼星号"
		"argus": return "百眼巨人号"
		"kirov": return "基洛夫号"
		"pobeda": return "胜利号"
		"gnevny": return "愤怒号"
		"bismarck": return "俾斯麦号"
		"prinz_eugen": return "欧根亲王号"
		"u_47": return "U-47"
		"yamato": return "大和号"
		"aurora": return "阿芙乐尔号"
		"hindenburg": return "兴登堡号"
		"shimakaze": return "岛风号"
		"hai_shih": return "海狮号"
		"yukikaze": return "雪风号"
		"hosho": return "凤翔号"
		"ning_hai": return "宁海号"
		"anshan": return "鞍山号"
		"chongqing": return "重庆号"
		"fletcher": return "弗莱彻号"
		"cleveland": return "克利夫兰号"
		"baltimore": return "巴尔的摩号"
		"wahoo": return "刺尾鱼号"
		"jervis": return "杰维斯号"
		"belfast": return "贝尔法斯特号"
		"illustrious": return "光辉号"
		"upholder": return "拥护者号"
		"tashkent": return "塔什干号"
		"chapayev": return "恰巴耶夫号"
		"gangut": return "甘古特号"
		"k_21": return "K-21号"
		"z23": return "Z23号"
		"nurnberg": return "纽伦堡号"
		"scharnhorst": return "沙恩霍斯特号"
		"graf_zeppelin": return "齐柏林伯爵号"
		"akizuki": return "秋月号"
		"takao": return "高雄号"
		"shokaku": return "翔鹤号"
		"i_19": return "伊-19号"
		"yat_sen": return "逸仙号"
		"chang_chun": return "长春号"
		"dingyuan": return "定远号"
		"hai_lung": return "海龙号"
		_: return "未知角色"
