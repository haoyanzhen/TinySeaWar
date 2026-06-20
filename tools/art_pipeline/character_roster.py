from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
CHARACTER_DOC = ROOT / "docs" / "41_character_art_design.md"

SHIP_CLASS_MAP = {
    "驱逐": "destroyer",
    "轻巡": "light_cruiser",
    "重巡": "heavy_cruiser",
    "战列": "battleship",
    "航母": "carrier",
    "潜艇": "submarine",
}

CHARACTER_ID_ALIASES = {
    "企业号 USS Enterprise CV-6": "enterprise_cv6",
    "衣阿华号 USS Iowa BB-61": "iowa",
    "圣地亚哥号 USS San Diego CL-53": "san_diego",
    "沃德号 USS Ward": "ward",
    "厌战号 HMS Warspite": "warspite",
    "胡德号 HMS Hood": "hood",
    "天狼星号 HMS Sirius": "sirius",
    "百眼巨人号 HMS Argus": "argus",
    "阿芙乐尔号 Aurora": "aurora",
    "基洛夫号 Kirov": "kirov",
    "胜利号 Pobeda": "pobeda",
    "愤怒号 Gnevny": "gnevny",
    "俾斯麦号 Bismarck": "bismarck",
    "欧根亲王号 Prinz Eugen": "prinz_eugen",
    "兴登堡号 Hindenburg": "hindenburg",
    "U-47": "u_47",
    "大和号 Yamato": "yamato",
    "雪风号 Yukikaze": "yukikaze",
    "岛风号 Shimakaze": "shimakaze",
    "凤翔号 Hosho": "hosho",
    "宁海号 Ning Hai": "ning_hai",
    "鞍山号 Anshan": "anshan",
    "重庆号 ROCS Chongqing": "chongqing",
    "海狮号 ROCS Hai Shih": "hai_shih",
}


@dataclass(frozen=True)
class CharacterRosterEntry:
    character_id: str
    prototype: str
    faction: str
    period: str
    ship_class_cn: str
    ship_class: str
    level: str
    personality: str
    combat_role: str
    art_direction: str
    asset_focus: str


def _fallback_character_id(prototype: str) -> str:
    ascii_tokens = re.findall(r"[A-Za-z0-9]+", prototype)
    if not ascii_tokens:
        raise ValueError(f"Cannot derive character id from prototype: {prototype}")
    token = "_".join(ascii_tokens).lower()
    return token.replace("cv_6", "cv6").replace("bb_61", "bb61")


def _split_table_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def load_roster(doc_path: Path = CHARACTER_DOC) -> list[CharacterRosterEntry]:
    entries: list[CharacterRosterEntry] = []
    for line in doc_path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| "):
            continue
        cells = _split_table_row(line)
        if len(cells) != 9 or cells[0] in {"角色原型", "---"}:
            continue
        ship_class_cn = cells[3]
        if ship_class_cn not in SHIP_CLASS_MAP:
            raise ValueError(f"Unknown MVP ship class in {doc_path}: {ship_class_cn}")
        prototype = cells[0]
        entries.append(
            CharacterRosterEntry(
                character_id=CHARACTER_ID_ALIASES.get(prototype, _fallback_character_id(prototype)),
                prototype=prototype,
                faction=cells[1],
                period=cells[2],
                ship_class_cn=ship_class_cn,
                ship_class=SHIP_CLASS_MAP[ship_class_cn],
                level=cells[4],
                personality=cells[5],
                combat_role=cells[6],
                art_direction=cells[7],
                asset_focus=cells[8],
            )
        )
    if not entries:
        raise ValueError(f"No character rows found in {doc_path}")
    duplicate_ids = sorted(
        character_id
        for character_id in {entry.character_id for entry in entries}
        if sum(1 for entry in entries if entry.character_id == character_id) > 1
    )
    if duplicate_ids:
        raise ValueError(f"Duplicate character ids in roster: {', '.join(duplicate_ids)}")
    return entries


def roster_by_id() -> dict[str, CharacterRosterEntry]:
    return {entry.character_id: entry for entry in load_roster()}


def ship_classes_by_id() -> dict[str, str]:
    return {entry.character_id: entry.ship_class for entry in load_roster()}
