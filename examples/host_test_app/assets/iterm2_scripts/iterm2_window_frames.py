import json

try:
    import iterm2
except Exception as e:
    print(json.dumps({"error": f"iterm2 module not available: {e}", "windows": []}, ensure_ascii=False))
    raise SystemExit(0)


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
    windows = []

    for win in app.terminal_windows:
        try:
            num = int(getattr(win, "window_number", 0))
        except Exception:
            num = 0
        f = await get_frame(win)
        if not f:
            continue
        try:
            windows.append(
                {
                    "windowNumber": num,
                    "rawWindowFrame": {
                        "x": float(f.origin.x),
                        "y": float(f.origin.y),
                        "w": float(f.size.width),
                        "h": float(f.size.height),
                    },
                }
            )
        except Exception:
            pass

    print(json.dumps({"windows": windows}, ensure_ascii=False))


if __name__ == "__main__":
    iterm2.run_until_complete(main)

