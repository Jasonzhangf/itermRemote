import json
import sys
import time

try:
    import iterm2
except Exception as e:
    print(json.dumps({"error": f"iterm2 module not available: {e}"}, ensure_ascii=False))
    raise SystemExit(0)

try:
    import Quartz
    from Quartz import (
        CGWindowListCopyWindowInfo,
        kCGNullWindowID,
        kCGWindowListOptionOnScreenOnly,
        kCGWindowListExcludeDesktopElements,
    )
except Exception:
    Quartz = None

SESSION_ID = sys.argv[1] if len(sys.argv) > 1 else ""


def _find_iterm2_cg_window_id_by_owner(rawWindowFrame=None):
    """Return first iTerm2 CGWindowID (best-effort)."""
    if Quartz is None:
        return None
    try:
        window_list = CGWindowListCopyWindowInfo(
            kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
            kCGNullWindowID,
        )
        for win_info in window_list:
            owner_name = win_info.get("kCGWindowOwnerName", "")
            # Filter by iTerm2 owner
            if "iterm" not in str(owner_name).lower():
                continue
            wid = win_info.get("kCGWindowNumber")
            if not isinstance(wid, int) or wid <= 0:
                continue
            # If rawWindowFrame provided, match by frame bounds.
            if rawWindowFrame:
                bounds = win_info.get("kCGWindowBounds", {})
                wx = bounds.get("X", 0)
                wy = bounds.get("Y", 0)
                ww = bounds.get("Width", 0)
                wh = bounds.get("Height", 0)
                # CGWindow bounds are in global coords, but macOS may report
                # slightly different Y due to menu bar / system UI.
                # Match primarily by X/Width/Height, and allow larger Y slack.
                if (abs(wx - rawWindowFrame.get("x", 0)) < 10 and
                    abs(wy - rawWindowFrame.get("y", 0)) < 80 and
                    abs(ww - rawWindowFrame.get("w", 0)) < 20 and
                    abs(wh - rawWindowFrame.get("h", 0)) < 20):
                    return wid
                # Not a match, continue searching.
                continue
            # No rawWindowFrame: return first iTerm2 window.
            return wid
    except Exception:
        pass
    return None


async def get_frame(obj):
    try:
        fn = getattr(obj, "async_get_frame", None)
        if fn:
            return await fn()
    except Exception:
        pass
    try:
        return obj.frame
    except Exception:
        return None


def subtree_size(node):
    try:
        if isinstance(node, iterm2.session.Session):
            f = node.frame
            return float(f.size.width), float(f.size.height)
        if isinstance(node, iterm2.session.Splitter):
            if getattr(node, "_Splitter__vertical", False):
                w = 0.0
                h = 0.0
                for c in node.children:
                    cw, ch = subtree_size(c)
                    w += cw
                    if ch > h:
                        h = ch
                return w, h
            else:
                w = 0.0
                h = 0.0
                for c in node.children:
                    cw, ch = subtree_size(c)
                    if cw > w:
                        w = cw
                    h += ch
                return w, h
    except Exception:
        pass
    return 0.0, 0.0


def node_bounds(node):
    try:
        if isinstance(node, iterm2.session.Session):
            f = node.frame
            x0 = float(f.origin.x)
            y0 = float(f.origin.y)
            x1 = x0 + float(f.size.width)
            y1 = y0 + float(f.size.height)
            return x0, y0, x1, y1
        if isinstance(node, iterm2.session.Splitter):
            xs = []
            ys = []
            xe = []
            ye = []
            for c in node.children:
                b = node_bounds(c)
                if b:
                    xs.append(b[0])
                    ys.append(b[1])
                    xe.append(b[2])
                    ye.append(b[3])
            if xs:
                return min(xs), min(ys), max(xe), max(ye)
    except Exception:
        pass
    return None


def assign_layout_frames(node, ox, oy, out):
    try:
        if isinstance(node, iterm2.session.Session):
            f = node.frame
            out[node.session_id] = {
                "x": ox + float(f.origin.x),
                "y": oy + float(f.origin.y),
                "w": float(f.size.width),
                "h": float(f.size.height),
            }
            return
        if isinstance(node, iterm2.session.Splitter):
            vertical = getattr(node, "_Splitter__vertical", False)
            mins = []
            for c in node.children:
                b = node_bounds(c)
                if b:
                    mins.append(round(b[0 if vertical else 1], 3))
            distinct = len(set(mins)) if mins else 0
            if vertical:
                if distinct > 1:
                    for c in node.children:
                        assign_layout_frames(c, ox, oy, out)
                else:
                    x = ox
                    for c in node.children:
                        assign_layout_frames(c, x, oy, out)
                        cw, _ = subtree_size(c)
                        x += cw
            else:
                if distinct > 1:
                    for c in node.children:
                        assign_layout_frames(c, ox, oy, out)
                else:
                    y = oy
                    for c in node.children:
                        assign_layout_frames(c, ox, y, out)
                        _, ch = subtree_size(c)
                        y += ch
    except Exception:
        pass


async def main(connection):
    app = await iterm2.async_get_app(connection)
    target = None
    target_win = None
    target_tab = None

    for win in app.terminal_windows:
        for tab in win.tabs:
            for sess in tab.sessions:
                if sess.session_id == SESSION_ID:
                    target = sess
                    target_win = win
                    target_tab = tab
                    break
            if target:
                break
        if target:
            break

    if not target:
        print(json.dumps({"error": f"session not found: {SESSION_ID}"}, ensure_ascii=False))
        return

    try:
        await target.async_activate()
    except Exception:
        pass
    try:
        fn = getattr(target_tab, "async_select", None)
        if fn:
            await fn()
    except Exception:
        pass
    try:
        await target_win.async_activate()
    except Exception:
        pass

    try:
        time.sleep(0.05)
    except Exception:
        pass

    layout_frames = {}
    layout_w = 0.0
    layout_h = 0.0
    try:
        root = target_tab.root
        layout_w, layout_h = subtree_size(root)
        assign_layout_frames(root, 0.0, 0.0, layout_frames)
    except Exception:
        layout_frames = {}
        layout_w = 0.0
        layout_h = 0.0

    # Use window_number as matchable id.
    try:
        win_number = int(getattr(target_win, "window_number", 1))
    except Exception:
        win_number = 1

    out = {
        "sessionId": target.session_id,
        "windowId": win_number,
        # CGWindowID used by ScreenCaptureKit for direct window capture.
        # This intentionally bypasses flutter_webrtc's DesktopCapturer sourceId mapping.
        "cgWindowId": None,
    }

    try:
        f = await get_frame(target)
        root_bounds = None
        try:
            root_bounds = node_bounds(target_tab.root)
        except Exception:
            root_bounds = None
        wf = await get_frame(target_win)

        # Always include layout-based frames for overlay/debug (best-effort).
        lf = layout_frames.get(target.session_id)
        if lf and layout_w > 0 and layout_h > 0:
            out["layoutFrame"] = lf
            out["layoutWindowFrame"] = {
                "x": 0.0,
                "y": 0.0,
                "w": float(layout_w),
                "h": float(layout_h),
            }

        if f and root_bounds:
            minx, miny, maxx, maxy = root_bounds
            ww = float(maxx - minx)
            wh = float(maxy - miny)
            if ww > 0 and wh > 0:
                out["frame"] = {
                    "x": float(f.origin.x),
                    "y": float(f.origin.y),
                    "w": float(f.size.width),
                    "h": float(f.size.height),
                }
                out["windowFrame"] = {
                    "x": float(minx),
                    "y": float(miny),
                    "w": float(ww),
                    "h": float(wh),
                }
        if wf:
            out["rawWindowFrame"] = {
                "x": float(wf.origin.x),
                "y": float(wf.origin.y),
                "w": float(wf.size.width),
                "h": float(wf.size.height),
            }
            try:
                out["cgWindowId"] = _find_iterm2_cg_window_id_by_owner(out["rawWindowFrame"])
            except Exception:
                out["cgWindowId"] = _find_iterm2_cg_window_id_by_owner()
    except Exception:
        pass

    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    iterm2.run_until_complete(main)
