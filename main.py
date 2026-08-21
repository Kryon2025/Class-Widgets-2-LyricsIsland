import json
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional

from loguru import logger
from PySide6.QtCore import Signal, Slot, Property

from ClassWidgets.SDK import CW2Plugin, PluginAPI

# 常量定义
WIDGET_ID = "com.lyricsisland"
SERVER_HOST = "127.0.0.1"
SERVER_PORT = 50063
DEFAULT_LYRIC = "等待音乐软件侧传输歌词..."

# 当前后端实例（HTTP 处理线程通过它安全更新歌词）
_backend: Optional["Plugin"] = None


class LyricsHandler(BaseHTTPRequestHandler):
    """接收音乐软件推送歌词的 HTTP 处理器"""

    def do_POST(self):
        if self.path != "/component/lyrics/lyrics/":
            self._send_error(404, "Not Found")
            return

        try:
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length == 0:
                raise ValueError("Empty request body")

            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode("utf-8"))

            lyric = data.get("lyric")
            if lyric is None:
                raise ValueError("Missing 'lyric' field in request")
            extra = data.get("extra") or ""

            # 跨线程安全：信号自动排队到 Qt 主线程
            backend = _backend
            if backend is not None:
                backend.set_lyrics(lyric, extra)

            self._send_response(200, "OK")

        except json.JSONDecodeError:
            logger.error("Invalid JSON format")
            self._send_error(400, "Invalid JSON format")
        except ValueError as e:
            logger.error(f"Invalid request: {str(e)}")
            self._send_error(400, str(e))
        except Exception as e:
            logger.error(f"Server error: {str(e)}")
            self._send_error(500, "Internal Server Error")

    def _send_response(self, code: int, message: str):
        self.send_response(code)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(message.encode())

    def _send_error(self, code: int, message: str):
        self.send_response(code)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        error_response = json.dumps({"error": message})
        self.wfile.write(error_response.encode())

    def log_message(self, format, *args):
        """禁用默认访问日志"""
        return


class HTTPServerWithStop(HTTPServer):
    """可停止的 HTTP 服务器"""

    def stop(self):
        # shutdown() 中断 serve_forever() 的阻塞等待；server_close() 释放监听端口
        self.shutdown()
        self.server_close()


class Plugin(CW2Plugin):
    """歌词岛组件：接收并显示实时歌词"""

    lyricsChanged = Signal()

    def __init__(self, api: PluginAPI):
        super().__init__(api)
        global _backend
        _backend = self
        self._lyric = ""
        self._extra = ""
        self._status = "waiting"  # waiting / ok
        self.server: Optional[HTTPServerWithStop] = None
        self._server_thread: Optional[threading.Thread] = None

    # ---- QML 可读属性 ----
    def _get_lyric(self):
        return self._lyric

    def _get_extra(self):
        return self._extra

    def _get_status(self):
        return self._status

    lyricText = Property(str, _get_lyric, notify=lyricsChanged)
    extraText = Property(str, _get_extra, notify=lyricsChanged)
    lyricStatus = Property(str, _get_status, notify=lyricsChanged)

    @Slot(str, str)
    def set_lyrics(self, lyric: str, extra: str = ""):
        """更新歌词（HTTP 线程调用，信号自动排队到主线程）"""
        self._lyric = lyric
        self._extra = extra
        self._status = "ok"
        self.lyricsChanged.emit()

    def on_load(self):
        super().on_load()
        self.api.widgets.register(
            widget_id=WIDGET_ID,
            name="歌词",
            qml_path="qml/lyrics.qml",
            settings_qml="qml/lyrics-settings.qml",
            backend_obj=self,
            default_settings={
                "lyric_font_size": 16,   # 原文字号（px）
                "extra_font_size": 12,   # 译文字号（px）
                "anim_mode": "off",      # 逐字动画：off=关闭 / float=上浮
                "scroll_seconds": 8,     # 长歌词滚动时长（秒）
                "scroll_delay": 0.5,     # 滚动前停顿（秒）
                "auto_show": True,       # 灵动显示：有歌词弹出，无歌词隐藏
                "lyric_color": "white",  # 主歌词颜色：white / black / theme
            },
        )
        self._start_server()
        print(f"[lyricsisland] 插件已加载，服务端口 {SERVER_PORT}")

    def on_unload(self):
        self._stop_server()
        print("[lyricsisland] 插件已卸载")

    # ---- HTTP 服务 ----
    def _start_server(self):
        try:
            # 主线程创建（构造时完成 bind，失败立即可知），线程只运行事件循环
            self.server = HTTPServerWithStop((SERVER_HOST, SERVER_PORT), LyricsHandler)
        except OSError as e:
            # 端口被占用（如旧实例未释放）：不阻塞插件
            logger.error(f"Lyrics server failed to bind {SERVER_HOST}:{SERVER_PORT}: {e}")
            self.server = None
            return
        except Exception as e:
            logger.error(f"Lyrics server error: {e}")
            self.server = None
            return
        logger.info(f"Lyrics server started at http://{SERVER_HOST}:{SERVER_PORT}")
        self._server_thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self._server_thread.start()

    def _stop_server(self):
        server = self.server
        self.server = None
        if server:
            try:
                server.stop()
                logger.info("Lyrics server stopped")
            except Exception as e:
                logger.error(f"Failed to stop lyrics server: {e}")
        if self._server_thread and self._server_thread.is_alive():
            self._server_thread.join(2)
        self._server_thread = None
