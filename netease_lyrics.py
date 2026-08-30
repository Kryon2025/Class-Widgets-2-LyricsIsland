"""
netease_lyrics.py
网易云音乐歌词获取：歌曲搜索匹配与 LRC 解析。

纯逻辑、无 Qt 依赖，便于独立测试。接口：
- find_lyrics(title, artist, duration_ms) -> (song | None, [(time_ms, text), ...])
  网络异常向上抛出，由调用方决定是否缓存。

匹配策略说明：
网易云音乐的无 Cookie 搜索会把 VIP 原曲排到很靠后的位置（实测原曲在第 70 名开外），
因此需要拉取较多结果（limit=100）并按以下权重打分挑出正确版本：
    3.0 × 标题相似度 + 1.5 × 艺人相似度 + 1.0 × 时长接近度
时长接近度尤其重要：同一首歌的翻唱/Live 版歌词时间轴对不上，靠 SMTC 时长排除。
"""

import json
import re
import time
import unicodedata
import urllib.parse
import urllib.request
from collections import Counter

_SEARCH_URL = "https://music.163.com/api/search/get/web"
_LYRIC_URL = "https://music.163.com/api/song/lyric"

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ),
    "Referer": "https://music.163.com/",
}
_TIMEOUT = 8
_RETRIES = 2
_SEARCH_LIMIT = 100

_ACCEPT_SCORE = 3.0    # 低于此分视为无匹配
_STRONG_SCORE = 4.5    # 高于此分无需用第二个查询再搜一次

# 标题归一化时剔除的字符：空白、连接符、各类括号引号与常见标点
_STRIP_CHARS = re.compile(r"[\s\-—–_·・'\"“”‘’【】\[\]（）()<>《》,，.。!！?？:：]")
# 艺人字段按这些分隔符拆分（SMTC 常见 "A / B"、"A feat. B"）
_ARTIST_SPLIT = re.compile(r"[&/、,，;；]|feat\.|ft\.|featuring", re.I)


def _norm(s):
    """归一化：NFKC（全半角统一）→ 小写 → 去标点空白。"""
    if not s:
        return ""
    s = unicodedata.normalize("NFKC", str(s)).lower()
    return _STRIP_CHARS.sub("", s)


def _dice(seq_a, seq_b):
    """Dice 系数：2×交集 / 总量。seq 为字符或二元组列表。"""
    if not seq_a or not seq_b:
        return 0.0
    common = Counter(seq_a) & Counter(seq_b)
    inter = sum(common.values())
    return 2.0 * inter / (len(seq_a) + len(seq_b))


def _similarity(a, b):
    """混合相似度：max(二元组 Dice, 字符 Dice)。

    不用 difflib——CW2 的 PyInstaller 运行时不包含它。
    二元组 Dice 对拉丁字符串区分度高；字符 Dice 容忍繁简体/单字差异
    （如 "周杰倫" vs "周杰伦"）。低于 0.5 的假相似（如 "kenshiyonezu"
    vs "kobasolo" 碰巧共享 k/o/s）直接归零。
    """
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    if a in b or b in a:
        return 0.9
    if len(a) == 1 or len(b) == 1:
        return 0.0
    bigram = _dice([a[i:i + 2] for i in range(len(a) - 1)],
                   [b[i:i + 2] for i in range(len(b) - 1)])
    chars = _dice(list(a), list(b))
    ratio = max(bigram, chars)
    return ratio if ratio >= 0.5 else 0.0


def _title_score(want, got):
    return _similarity(_norm(want), _norm(got))


def _artist_score(want, got_artists):
    want_tokens = [_norm(t) for t in _ARTIST_SPLIT.split(want or "")]
    want_tokens = [t for t in want_tokens if t]
    if not want_tokens:
        return 0.0
    best = 0.0
    for g in got_artists or []:
        gn = _norm(str(g))
        if not gn:
            continue
        for w in want_tokens:
            best = max(best, _similarity(w, gn))
    return best


def _duration_score(want_ms, got_ms):
    if not want_ms or want_ms <= 0 or not got_ms:
        return 0.5  # SMTC 没有时长信息时给中性分
    delta = abs(want_ms - got_ms)
    if delta <= 2000:
        return 1.0
    if delta >= 15000:
        return 0.0
    return 1.0 - (delta - 2000) / 13000.0


def score_song(song, title, artist, duration_ms):
    """给单条搜索结果打分，满分 5.5。"""
    t = _title_score(title, song.get("name", ""))
    a = _artist_score(artist, song.get("artists") or [])
    d = _duration_score(duration_ms, song.get("duration") or 0)
    return 3.0 * t + 1.5 * a + 1.0 * d


# ---- HTTP ----

def _get_json(url):
    last_err = None
    for _ in range(_RETRIES):
        try:
            req = urllib.request.Request(url, headers=_HEADERS)
            with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
                return json.load(resp)
        except Exception as e:
            last_err = e
            time.sleep(0.5)
    raise last_err


def search_songs(query, limit=_SEARCH_LIMIT):
    params = urllib.parse.urlencode({"s": query, "type": 1, "limit": limit, "offset": 0})
    data = _get_json(f"{_SEARCH_URL}?{params}")
    return (data.get("result") or {}).get("songs") or []


def fetch_lyrics(song_id):
    """同时抓取原词 lrc 与翻译 tlyric，返回 (lrc_text, tlrc_text)。"""
    data = _get_json(f"{_LYRIC_URL}?id={song_id}&lv=1&kv=1&tv=-1")
    lrc = ((data.get("lrc") or {}).get("lyric")) or ""
    tlrc = ((data.get("tlyric") or {}).get("lyric")) or ""
    return lrc, tlrc


# ---- LRC 解析 ----

def parse_lrc(lrc_text):
    """解析 LRC 文本为 [(time_ms, text), ...]，按时间升序。

    支持：一行多时间戳、[mm:ss.xx] / [mm:ss:xx] / 整数秒、[offset:±ms] 元数据；
    丢弃空行与无文字的占位时间戳。
    """
    offset_ms = 0
    entries = []
    for raw in (lrc_text or "").splitlines():
        line = raw.strip()
        if not line:
            continue

        # 独立的元数据行 [ti:..] [ar:..] [offset:..] 等
        meta = re.fullmatch(r"\[([a-zA-Z#]+):([^\]]*)\]", line)
        if meta:
            if meta.group(1).lower() == "offset":
                try:
                    # 正 offset 表示歌词整体提前（时间轴前移）
                    offset_ms = int(meta.group(2).strip())
                except ValueError:
                    pass
            continue

        # 行首连续的时间戳组
        stamps = []
        pos = 0
        while True:
            m = re.match(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]", line[pos:])
            if not m:
                break
            stamps.append(m)
            pos += m.end()
        if not stamps:
            continue

        text = line[pos:].strip()
        if not text:
            continue
        for m in stamps:
            ms = (int(m.group(1)) * 60 + int(m.group(2))) * 1000
            frac = m.group(3)
            if frac:
                ms += int(frac.ljust(3, "0")[:3])
            entries.append((ms - offset_ms, text))

    entries.sort(key=lambda kv: kv[0])
    return entries


# 制作信息行（作词/作曲/编曲等）不与翻译合并，避免开头把第一句的翻译贴到制作信息上
_CREDIT_START = re.compile(
    r"^(?:作词|作曲|编曲|制作人?|监制|录音|混音|母带|词曲|原唱|翻唱|cover|"
    r"OP|SP|文案|出品|统筹|和声|吉他|贝斯|鼓|键盘|钢琴|弦乐|制作)[\s:：]"
)


def align_translation(lines, trans, tol_ms=200):
    """把翻译按时间戳一对一对齐到原词行，返回 (t, 原文, 翻译|None) 三元组。

    网易云 tlyric 与原词逐行同时间戳精确对齐，因此以精确匹配为主，
    仅留 tol_ms 小容差应对个别偏移；一个翻译只归属一个原词行，
    避免密集行被同一个翻译重复贴上。制作信息行不匹配翻译。
    """
    if not lines or not trans:
        return [(t, text, None) for t, text in lines]
    used = [False] * len(trans)
    result = []
    for t, text in lines:
        if _CREDIT_START.match(text):
            result.append((t, text, None))
            continue
        best_i, best_d = -1, tol_ms + 1
        for i, (tt, _) in enumerate(trans):
            if used[i]:
                continue
            d = abs(tt - t)
            if d < best_d:
                best_d, best_i = d, i
        if best_i >= 0:
            used[best_i] = True
            result.append((t, text, trans[best_i][1]))
        else:
            result.append((t, text, None))
    return result


# ---- 对外入口 ----

def find_lyrics(title, artist, duration_ms):
    """搜索并匹配歌曲、抓取歌词（含翻译，翻译拼进原文后括号内）。

    返回 (song_dict | None, lines)。song 为 None 表示没有足够相似的匹配；
    网络错误向上抛出（此时不应缓存结果，下次换歌还能重试）。
    """
    queries = []
    if title and artist:
        queries.append(f"{title} {artist}")
    if title:
        queries.append(title)

    best_song, best_score = None, 0.0
    for q in queries:
        songs = search_songs(q)
        for s in songs:
            sc = score_song(s, title, artist, duration_ms)
            if sc > best_score:
                best_song, best_score = s, sc
        if best_score >= _STRONG_SCORE:
            break

    if best_song is None or best_score < _ACCEPT_SCORE:
        return None, []

    lrc, tlrc = fetch_lyrics(best_song["id"])
    lines = parse_lrc(lrc)
    trans = parse_lrc(tlrc) if tlrc else []
    return best_song, align_translation(lines, trans)
