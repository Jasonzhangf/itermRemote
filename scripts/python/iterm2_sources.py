import json

try:
    import iterm2
except Exception as e:
    print(json.dumps({"error": f"iterm2 module not available: {e}", "panels": []}, ensure_ascii=False))
    raise SystemExit(0)


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


async def main(connection):
    app = await iterm2.async_get_app(connection)
    panels = []
    selected = None

    # Make windowId stable and matchable: use window.window_number (small int)
    # instead of the internal window_id string.
    win_num_map = {}

    try:
        w = app.current_terminal_window
        if w and w.current_tab and w.current_tab.current_session:
            selected = w.current_tab.current_session.session_id
    except Exception:
        selected = None

    win_idx = 0
    for win in app.terminal_windows:
        win_idx += 1
        try:
            n = int(getattr(win, "window_number", win_idx))
            if n <= 0:
                n = win_idx
            win_num_map[getattr(win, "window_id", None)] = n
        except Exception:
            win_num_map[getattr(win, "window_id", None)] = win_idx

        cg_window_id = None
        try:
            # macOS: use Window.screen_number (CGWindowID) when available.
            cg_window_id = int(getattr(win, "screen_number", 0))
            if cg_window_id <= 0:
                cg_window_id = None
        except Exception:
            cg_window_id = None

        win_frame = await get_frame(win)
        raw_window_frame = None
        if win_frame:
            raw_window_frame = {
                "x": float(win_frame.origin.x),
                "y": float(win_frame.origin.y),
                "w": float(win_frame.size.width),
                "h": float(win_frame.size.height),
            }

        tab_idx = 0
        for tab in win.tabs:
            tab_idx += 1
            layout_frames = {}
            layout_w = 0.0
            layout_h = 0.0
            try:
                root = tab.root
                layout_w, layout_h = subtree_size(root)
                assign_layout_frames(root, 0.0, 0.0, layout_frames)
            except Exception:
                layout_frames = {}
                layout_w = 0.0
                layout_h = 0.0
            sess_idx = 0
            for sess in tab.sessions:
                sess_idx += 1
                try:
                    tab_title = await sess.async_get_variable("tab.title")
                except Exception:
                    tab_title = ""
                name = getattr(sess, "name", "") or ""
                title = f"{win_idx}.{tab_idx}.{sess_idx}"
                detail = " · ".join([p for p in [tab_title, name] if p])
                item = {
                    "id": sess.session_id,
                    "title": title,
                    "detail": detail,
                    "index": len(panels),
                    "windowId": win_num_map.get(getattr(win, "window_id", None), win_idx),
                    "cgWindowId": cg_window_id,
                }
                try:
                    sess_frame = await get_frame(sess)
                    if sess_frame and raw_window_frame:
                        item["frame"] = {
                            "x": float(sess_frame.origin.x),
                            "y": float(sess_frame.origin.y),
                            "w": float(sess_frame.size.width),
                            "h": float(sess_frame.size.height),
                        }
                        item["windowFrame"] = raw_window_frame

                    if raw_window_frame:
                        item["rawWindowFrame"] = raw_window_frame

                    # Keep layout-based frames for fallback/debug.
                    f = layout_frames.get(sess.session_id)
                    if f and layout_w > 0 and layout_h > 0:
                        item["layoutFrame"] = f
                        item["layoutWindowFrame"] = {
                            "x": 0.0,
                            "y": 0.0,
                            "w": float(layout_w),
                            "h": float(layout_h),
                        }
                except Exception:
                    pass
                panels.append(item)

    print(json.dumps({"panels": panels, "selectedSessionId": selected}, ensure_ascii=False))


if __name__ == "__main__":
    iterm2.run_until_complete(main)
