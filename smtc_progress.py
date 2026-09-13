# -*- coding: utf-8 -*-
"""smtc_progress.py
轻量 SMTC 读取器：只取当前媒体会话的 歌名 / 歌手 / 播放位置 / 总时长 / 播放状态，
不做任何歌词匹配。用于给歌词岛提供真实播放进度。

winrt 仅在 start() 里按需导入，缺库时不影响插件其余功能。
"""

import asyncio
import threading

from loguru import logger
from PySide6.QtCore import QObject, Signal

_STATUS_PLAYING = 4
_POLL_SECONDS = 0.5


class SmtcProgress(QObject):
    """从 Windows SMTC 会话读取播放进度（含歌曲标识，供核验用）。"""

    updated = Signal(str, str, int, int, bool, str)   # title, artist, pos_ms, dur_ms, playing, raw
    thumbnail = Signal(str, "QByteArray")             # title, 封面图字节
    started = Signal(bool)                       # 是否成功启动（winrt 可用）

    def __init__(self, parent=None):
        super().__init__(parent)
        self._loop = None
        self._thread = None
        self._running = False
        self._thumb_title = None
        self._thumbs_enabled = True

    # ---- 主线程调用 ----
    def start(self):
        if self._thread is not None:
            return
        try:
            from winrt.windows.media.control import (  # noqa: F401
                GlobalSystemMediaTransportControlsSessionManager,
            )
        except Exception:
            # 兜底：使用插件自带的 libs/winrt
            try:
                import os
                import sys

                sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "libs"))
                from winrt.windows.media.control import (  # noqa: F401
                    GlobalSystemMediaTransportControlsSessionManager,
                )
            except Exception as e:
                logger.error(f"[smtc] winrt 不可用，进度读取关闭: {e}")
                self.started.emit(False)
                return
        self._running = True
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()
        self.started.emit(True)
        logger.info("[smtc] 进度读取已启动")

    def set_thumbnails_enabled(self, on):
        """SMTC 体检未通过时关掉封面抓取，省掉解码与落盘占用。"""
        on = bool(on)
        if on == self._thumbs_enabled:
            return
        self._thumbs_enabled = on
        if on:
            self._thumb_title = None   # 重新允许后补抓一次

    def stop(self):
        self._running = False
        loop, self._loop = self._loop, None
        thread, self._thread = self._thread, None
        if loop is not None:
            try:
                loop.call_soon_threadsafe(loop.stop)
            except Exception:
                pass
        if thread and thread.is_alive():
            thread.join(1)
        logger.info("[smtc] 进度读取已停止")

    # ---- asyncio 线程 ----
    def _run_loop(self):
        asyncio.set_event_loop(self._loop)
        try:
            self._loop.run_until_complete(self._poll())
        except Exception as e:
            logger.error(f"[smtc] poll loop 异常: {e}")

    async def _poll(self):
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionManager as MediaManager,
        )
        manager = None
        while self._running:
            try:
                if manager is None:
                    manager = await MediaManager.request_async()
                session = manager.get_current_session()
                if session is None:
                    self._thumb_title = None
                    self.updated.emit("", "", 0, 0, False, "")
                else:
                    props = await session.try_get_media_properties_async()
                    title = (props.title or "") if props is not None else ""
                    artist = (props.artist or "") if props is not None else ""
                    pos_ms, dur_ms, raw = self._timeline(session)
                    playing = self._playing(session)
                    self.updated.emit(title, artist, pos_ms, dur_ms, playing, raw)
                    # 歌曲变化时抓一次封面
                    if self._thumbs_enabled and title and title != self._thumb_title:
                        self._thumb_title = title
                        data = await self._read_thumbnail(props)
                        if data:
                            self.thumbnail.emit(title, data)
            except Exception as e:
                logger.debug(f"[smtc] 读取失败: {e}")
                manager = None
            await asyncio.sleep(_POLL_SECONDS)

    @staticmethod
    async def _read_thumbnail(props):
        """读取 SMTC 媒体缩略图（专辑封面）字节。"""
        if props is None:
            return b""
        try:
            ref = getattr(props, "thumbnail", None)
            if ref is None:
                return b""
            stream = await ref.open_read_async()
            if stream is None or not stream.size:
                return b""
            from winrt.windows.storage.streams import DataReader

            reader = DataReader(stream)
            await reader.load_async(stream.size)
            n = reader.unconsumed_buffer_length
            if not n:
                return b""
            buf = reader.read_buffer(n)
            try:
                return bytes(memoryview(buf))
            except Exception:
                arr = bytearray(n)
                DataReader.from_buffer(buf).read_bytes(arr)
                return bytes(arr)
        except Exception as e:
            logger.debug(f"[lyricsisland] 读取封面失败: {e}")
            return b""

    @staticmethod
    def _ms(value):
        try:
            return int(value.total_seconds() * 1000) if value is not None else 0
        except Exception:
            return 0

    @classmethod
    def _timeline(cls, session):
        """读取播放位置与总时长。

        优先 end_time；为 0 时回退到 max_seek_time（不少播放器把总时长放这里）。
        """
        try:
            ti = session.get_timeline_properties()
            pos = cls._ms(getattr(ti, "position", None))
            end = cls._ms(getattr(ti, "end_time", None))
            mx = cls._ms(getattr(ti, "max_seek_time", None))
            mn = cls._ms(getattr(ti, "min_seek_time", None))
            dur = end if end > 0 else mx
            raw = f"pos={pos} end={end} max_seek={mx} min_seek={mn}"
            return max(0, pos), max(0, dur), raw
        except Exception:
            return 0, 0, "err"

    @staticmethod
    def _playing(session):
        try:
            return int(session.get_playback_info().playback_status) == _STATUS_PLAYING
        except Exception:
            return False
