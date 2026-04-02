"""Base class for WKWebView-backed NSWindows."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import objc
from AppKit import (
    NSApp, NSBackingStoreBuffered, NSMakeRect, NSMakeSize,
    NSObject, NSWindow,
    NSTitledWindowMask, NSClosableWindowMask,
    NSMiniaturizableWindowMask, NSResizableWindowMask,
)
from Foundation import NSURL

# WebKit is a separate framework
import WebKit
from WebKit import (
    WKWebView, WKWebViewConfiguration, WKUserContentController,
)

_UI_DIR = Path(__file__).parent / "ui"


class _BridgeHandler(NSObject):
    """Routes JS → Python messages."""

    def initWithCallback_(self, callback):
        self = objc.super(_BridgeHandler, self).init()
        self._callback = callback
        return self

    def userContentController_didReceiveScriptMessage_(self, controller, message):
        body = message.body()
        try:
            action = str(body["action"])
            payload = dict(body.get("payload") or {})
        except Exception:
            return
        self._callback(action, payload)


class _NavDelegate(NSObject):
    """Fires on_load() once the page finishes loading."""

    def initWithCallback_(self, callback):
        self = objc.super(_NavDelegate, self).init()
        self._callback = callback
        return self

    def webView_didFinishNavigation_(self, webView, navigation):
        if self._callback:
            self._callback()


class _WinDelegate(NSObject):
    def windowWillClose_(self, notif):
        pass  # keep alive; caller decides when to destroy


class WebViewWindow:
    """
    NSWindow containing a full-size WKWebView.

    Subclasses override:
      handle_message(action: str, payload: dict) — called for every JS postMessage
      on_load() — called once after the HTML finishes loading
    """

    def __init__(
        self,
        html_name: str,
        title: str,
        width: int,
        height: int,
        resizable: bool = True,
        min_size: tuple[int, int] | None = None,
    ):
        self._html_name = html_name
        self._title = title
        self._width = width
        self._height = height
        self._resizable = resizable
        self._min_size = min_size
        self._window: NSWindow | None = None
        self._webview: WKWebView | None = None
        # Keep ObjC objects alive
        self._bridge_handler = None
        self._nav_delegate = None
        self._win_delegate = None

    # ── Build ─────────────────────────────────────────────────────────────────

    def _build(self) -> None:
        style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
        if self._resizable:
            style |= NSResizableWindowMask

        win = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, self._width, self._height),
            style,
            NSBackingStoreBuffered,
            False,
        )
        win.setTitle_(self._title)
        win.setReleasedWhenClosed_(False)
        win.center()

        if self._min_size:
            win.setMinSize_(NSMakeSize(*self._min_size))

        win_del = _WinDelegate.alloc().init()
        win.setDelegate_(win_del)
        self._win_delegate = win_del

        # WKWebView
        ucc = WKUserContentController.alloc().init()
        bridge = _BridgeHandler.alloc().initWithCallback_(self.handle_message)
        ucc.addScriptMessageHandler_name_(bridge, "bridge")
        self._bridge_handler = bridge

        cfg = WKWebViewConfiguration.alloc().init()
        cfg.setUserContentController_(ucc)

        wv = WKWebView.alloc().initWithFrame_configuration_(
            win.contentView().bounds(), cfg
        )
        wv.setAutoresizingMask_(18)  # flexible width + height

        nav_del = _NavDelegate.alloc().initWithCallback_(self._on_load_internal)
        wv.setNavigationDelegate_(nav_del)
        self._nav_delegate = nav_del

        win.contentView().addSubview_(wv)

        self._window = win
        self._webview = wv

        self._load_html()

    def _load_html(self) -> None:
        html_path = _UI_DIR / f"{self._html_name}.html"
        url = NSURL.fileURLWithPath_(str(html_path))
        base = NSURL.fileURLWithPath_(str(_UI_DIR))
        self._webview.loadFileURL_allowingReadAccessToURL_(url, base)

    def _on_load_internal(self):
        self.on_load()

    # ── Public API ────────────────────────────────────────────────────────────

    def show(self) -> None:
        if self._window is None:
            self._build()
        self._window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)

    def send(self, action: str, payload: Any = None) -> None:
        """Push a message to JS: calls window.receive({action, payload})."""
        msg = json.dumps({"action": action, "payload": payload}, ensure_ascii=False)
        js = f"window.receive && window.receive({msg})"
        self._webview.evaluateJavaScript_completionHandler_(js, None)

    # ── Subclass hooks ────────────────────────────────────────────────────────

    def handle_message(self, action: str, payload: dict) -> None:  # noqa: B027
        """Override in subclass to handle JS → Python messages."""

    def on_load(self) -> None:  # noqa: B027
        """Override in subclass. Called once after HTML finishes loading."""
