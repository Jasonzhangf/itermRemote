import json

def main():
    panels = [
        {
            "id": "session-1",
            "title": "1.1.1",
            "detail": "bash",
            "index": 0,
            "frame": {"x": 0.0, "y": 0.0, "w": 400.0, "h": 300.0},
            "windowFrame": {"x": 0.0, "y": 0.0, "w": 800.0, "h": 600.0}
        },
        {
            "id": "session-2",
            "title": "1.1.2",
            "detail": "python",
            "index": 1,
            "frame": {"x": 400.0, "y": 0.0, "w": 400.0, "h": 300.0},
            "windowFrame": {"x": 0.0, "y": 0.0, "w": 800.0, "h": 600.0}
        }
    ]
    print(json.dumps({"panels": panels, "selectedSessionId": "session-1"}))

if __name__ == '__main__':
    main()
