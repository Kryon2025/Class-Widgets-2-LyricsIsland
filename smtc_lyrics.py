# -*- coding: utf-8 -*-
"""
smtc_lyrics.py
SMTC 歌词后端（Windows）：从新版网易云音乐等支持 SMTC 的播放器
获取当前歌曲信息，匹配网易云歌词库（联网搜索 LRC），按播放进度
实时输出当前歌词行。

流程：
- asyncio 工作线程订阅 SMTC 会话/换歌/时间线事件；
- 工作线程只通过排队 Signal 把数据交到主线程（QTimer / 缓存只允许主线程操作）；
- 换歌 → 后台线程网易云搜索匹配歌词（不阻塞 UI）→ 信号回主线程；
- 主线程 500ms 节拍插值播放进度，二分定位当前行，行变化时发 lyricReady。

防闪烁：
- 位置融合：正常播放时进度单调不减（防 SMTC 位置轻微回退导致行来回跳）；
  与插值偏差 > 3s（拖动/快进/快退）才完全信任 SMTC 位置。
- 行滞回：行索引前进立即切换；后退仅当大幅回退（拖动进度）才允许。
"""

import asyncio
import threading
import time

from loguru import logger
from PySide6.QtCore import QObject, QTimer, Signal

import netease_lyrics

# SMTC PlaybackStatus.Playing
_STATUS_PLAYING = 4

_TICK_MS = 500          # 进度行刷新节拍
_CACHE_MAX = 100        # (title, artist) -> lines 缓存上限
_DEBOUNCE_MS = 600      # 换歌时标题/艺人分字段先后到达，合并请求
_SEEK_TOLERANCE_MS = 3000  # 与插值偏差超过该值视为拖动/跳转
_BACK_TOLERANCE_MS = 1500  # 行回退容忍：位置落后该值以内不切回上一行


class SmtcLyricsBackend(QObject):
    """SMTC 歌词后端。"""

    lyricReady = Signal(str, str)     # lyric, extra(翻译)
    stateChanged = Signal(str)        # 状态：smtc_ready / smtc_error / no_session
    # 工作线程 → 主线程排队信号（QTimer / 缓存只允许主线程操作）
    mediaUpdated = Signal(str, str, int, int, bool, float)   # title, artist, pos, dur, playing, rate
    lyricsFetched = Signal(object, object)                   # key, lines

    def __init__(self, parent=None):
        super().__init__(parent)
        self._loop = None
        self._thread = None
        self._manager = None
        self._manager_token = None
        self._session = None
        self._session_id = None
        self._session_tokens = []

        # 主线程状态
        self._title = ""
        self._artist = ""
        self._lines = []              # [(time_ms, text, trans|None)]
        self._last_index = -1
        self._lines_key = None
        self._cache = {}
        self._gen = 0

        self._position_ms = 0
        self._duration_ms = 0
        self._playing = False
        self._rate = 1.0
        self._pos_stamp = 0.0

        self._debounce_title = ""
        self._debounce_artist = ""
        self._debounce_dur = 0
        self._debounce_timer = QTimer(self)
        self._debounce_timer.setSingleShot(True)
        self._debounce_timer.setInterval(_DEBOUNCE_MS)
        self._debounce_timer.timeout.connect(self._do_fetch_lyrics)
        self.mediaUpdated.connect(self._apply_media)      # 跨线程排队 → 主线程
        self.lyricsFetched.connect(self._apply_lyrics)    # 跨线程排队 → 主线程

        self._tick = QTimer(self)
        self._tick.setInterval(_TICK_MS)
        self._tick.timeout.connect(self._on_tick)

    # ---- 启动 / 停止（主线程调用） ----

    def start(self):
        if self._loop is not None:
            return
        try:
            from winrt.windows.media.control import GlobalSystemMediaTransportControlsSessionManager
            self._manager_cls = GlobalSystemMediaTransportControlsSessionManager
        except Exception as e:
            logger.error(f"SMTC lyrics: winrt import failed: {e}")
            self.stateChanged.emit("smtc_error")
            return

        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()
        asyncio.run_coroutine_threadsafe(self._bootstrap(), self._loop)
        self._tick.start()
        logger.info("SMTC lyrics: started")

    def stop(self):
        self._tick.stop()
        self._debounce_timer.stop()
        loop, self._loop = self._loop, None
        if loop is not None:
            try:
                asyncio.run_coroutine_threadsafe(self._shutdown(), loop)
            except Exception:
                pass
            try:
                loop.call_soon_threadsafe(loop.stop)
            except Exception:
                pass
        thread, self._thread = self._thread, None
        if thread and thread.is_alive():
            thread.join(1)

    async def _shutdown(self):
        try:
            if self._manager and self._manager_token is not None:
                self._manager.remove_sessions_changed(self._manager_token)
        except Exception:
            pass
        self._unsubscribe_sessions()

    # ---- asyncio 线程 ----

    def _run_loop(self):
        asyncio.set_event_loop(self._loop)
        self._loop.run_forever()

    async def _bootstrap(self):
        try:
            manager = await self._manager_cls.request_async()
            self._manager = manager
            try:
                self._manager_token = manager.add_sessions_changed(self._on_sessions_changed)
            except Exception as e:
                logger.warning(f"SMTC lyrics: sessions_changed subscribe failed: {e}")
            await self._sync_state()
            self.stateChanged.emit("smtc_ready")
            logger.info("SMTC lyrics: event-driven mode ready")
        except Exception as e:
            logger.error(f"SMTC lyrics: bootstrap failed: {e}")
            self.stateChanged.emit("smtc_error")

    def _on_sessions_changed(self, sender, args):
        if self._loop is not None:
            asyncio.run_coroutine_threadsafe(self._sync_state(), self._loop)

    def _on_any_session_event(self, sender, args):
        # 订阅全部会话而非仅当前会话——当前会话切换（另一应用开始播放）
        # 不一定伴随 sessions_changed 事件，事件到来时先刷新当前会话再拉取
        if self._loop is not None:
            asyncio.run_coroutine_threadsafe(self._light_sync(), self._loop)

    async def _sync_state(self):
        self._resubscribe_sessions()
        await self._fetch()

    async def _light_sync(self):
        self._update_current_session()
        await self._fetch()

    def _resubscribe_sessions(self):
        self._unsubscribe_sessions()
        try:
            sessions = list(self._manager.get_sessions())
        except Exception as e:
            logger.warning(f"SMTC lyrics: get_sessions failed: {e}")
            sessions = []
        for session in sessions:
            self._subscribe_session(session)
        self._update_current_session()

    def _subscribe_session(self, session):
        for name in ("media_properties_changed", "playback_info_changed", "timeline_properties_changed"):
            try:
                token = getattr(session, f"add_{name}")(self._on_any_session_event)
                self._session_tokens.append((session, f"remove_{name}", token))
            except Exception as e:
                logger.warning(f"SMTC lyrics: subscribe {name} failed: {e}")

    def _unsubscribe_sessions(self):
        for session, remover, token in self._session_tokens:
            try:
                getattr(session, remover)(token)
            except Exception:
                pass
        self._session_tokens = []

    def _update_current_session(self):
        session = self._manager.get_current_session() if self._manager else None
        new_id = None
        if session is not None:
            try:
                new_id = session.source_app_user_model_id
            except Exception:
                new_id = None
        if new_id == self._session_id:
            return
        logger.info(f"SMTC lyrics: current session -> {new_id}")
        self._session = session
        self._session_id = new_id

    async def _fetch(self):
        """拉取当前会话信息，经排队信号回主线程。"""
        try:
            session = self._session
            if session is None:
                self.mediaUpdated.emit("", "", 0, 0, False, 1.0)
                return
            props = await session.try_get_media_properties_async()
            title = props.title or ""
            artist = props.artist or ""
            position_ms, duration_ms = self._read_timeline(session)
            status, rate = self._read_playback(session)
            logger.debug(
                f"SMTC lyrics: fetch title={title!r} artist={artist!r} "
                f"pos={position_ms} dur={duration_ms} status={status}")
            self.mediaUpdated.emit(title, artist, position_ms, duration_ms,
                                   status == _STATUS_PLAYING, rate if rate else 1.0)
        except Exception as e:
            logger.debug(f"SMTC lyrics: fetch failed: {e}")

    def _read_timeline(self, session):
        try:
            ti = session.get_timeline_properties()
            pos = getattr(ti, "position", None)
            end = getattr(ti, "end_time", None)
            position_ms = int(pos.total_seconds() * 1000) if pos is not None else self._position_ms
            duration_ms = int(end.total_seconds() * 1000) if end is not None else self._duration_ms
            return position_ms, duration_ms
        except Exception as e:
            logger.debug(f"SMTC lyrics: get timeline failed: {e}")
            return self._position_ms, self._duration_ms

    def _read_playback(self, session):
        try:
            pb = session.get_playback_info()
            status = int(pb.playback_status)
            rate = getattr(pb, "playback_rate", None)
            return status, (float(rate) if rate else None)
        except Exception as e:
            logger.debug(f"SMTC lyrics: get playback info failed: {e}")
            return None, None

    # ---- 主线程：媒体状态应用（跨线程排队信号） ----

    def _apply_media(self, title, artist, position_ms, duration_ms, playing, rate):
        prev = self._current_position_ms()          # 上次插值位置（播放中已推进）
        self._playing = playing
        self._rate = rate if rate and rate > 0 else 1.0
        self._duration_ms = max(0, duration_ms)

        # 位置融合（防闪烁核心）：
        # - 正常播放：位置单调不减，取插值与新值的较大者，SMTC 轻微回退不回跳
        # - 暂停/停止：直接采用新值（无插值推进）
        # - 与插值偏差 > 3s（拖动进度/快进快退）：完全信任新值
        if not playing or abs(position_ms - prev) > _SEEK_TOLERANCE_MS:
            self._position_ms = max(0, position_ms)
        else:
            self._position_ms = max(prev, min(max(0, position_ms), prev + 5000))
        self._pos_stamp = time.monotonic()

        if title != self._title or artist != self._artist:
            self._title = title
            self._artist = artist
            self._on_song_changed(title, artist, self._duration_ms)
        else:
            self._step_line()

    def _current_position_ms(self):
        if not self._playing:
            return self._position_ms
        delta = (time.monotonic() - self._pos_stamp) * 1000.0 * self._rate
        pos = self._position_ms + delta
        if self._duration_ms > 0:
            pos = min(pos, float(self._duration_ms))
        return int(pos)

    # ---- 换歌：后台线程获取歌词 ----

    def _on_song_changed(self, title, artist, duration_ms):
        self._gen += 1
        self._lines = []
        self._last_index = -1
        self._lines_key = None
        if not title:
            return
        self._debounce_title = title
        self._debounce_artist = artist or ""
        self._debounce_dur = duration_ms
        self._debounce_timer.start()

    def _do_fetch_lyrics(self):
        title = self._debounce_title
        artist = self._debounce_artist
        key = (title, artist)
        if key in self._cache:
            self.lyricsFetched.emit(key, self._cache[key])
            return
        gen = self._gen
        duration_ms = self._debounce_dur
        threading.Thread(target=self._fetch_worker, args=(gen, key, title, artist, duration_ms), daemon=True).start()

    def _fetch_worker(self, gen, key, title, artist, duration_ms):
        try:
            song, lines = netease_lyrics.find_lyrics(title, artist, duration_ms)
        except Exception as e:
            logger.warning(f"SMTC lyrics: network error for {title!r}: {e}")
            return
        if gen != self._gen:
            return
        if song is None:
            logger.info(f"SMTC lyrics: no match on NetEase for {title!r} / {artist!r}")
            lines = [(0, title, None)]  # 无歌词时显示歌名，保证组件有内容
        else:
            logger.info(f"SMTC lyrics: matched {song.get('name')!r} (id={song.get('id')}), {len(lines)} lines")
        self.lyricsFetched.emit(key, lines)

    def _apply_lyrics(self, key, lines):
        self._cache[key] = lines
        while len(self._cache) > _CACHE_MAX:
            del self._cache[next(iter(self._cache))]
        already = key == self._lines_key
        self._lines = list(lines)
        self._lines_key = key
        if not already:
            self._last_index = -1
            self._step_line()

    # ---- 进度节拍：当前行 ----

    def _on_tick(self):
        self._step_line()

    def _step_line(self):
        if not self._lines:
            return
        pos = self._current_position_ms()
        idx = self._index_at(pos)
        if idx == self._last_index:
            return
        # 滞回：前进立即切换；回退仅当大幅回退（拖动进度/快退）才允许，
        # 否则忽略轻微回退，避免行在边界来回闪烁
        back_limit = (self._lines[self._last_index][0] - _BACK_TOLERANCE_MS
                      if 0 <= self._last_index < len(self._lines) else 0)
        if idx < self._last_index and pos > back_limit:
            return
        self._last_index = idx
        if idx >= 0:
            t, text, trans = self._lines[idx]
            self.lyricReady.emit(text, trans or "")

    def _index_at(self, pos_ms):
        lo, hi = 0, len(self._lines)
        while lo < hi:
            mid = (lo + hi) // 2
            if self._lines[mid][0] <= pos_ms:
                lo = mid + 1
            else:
                hi = mid
        return lo - 1
