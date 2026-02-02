import json
import sys

def main():
    session_id = sys.argv[1] if len(sys.argv) > 1 else ""
    print(json.dumps({
        "sessionId": session_id,
        "windowId": 1,
        "frame": {"x": 0.0, "y": 0.0, "w": 400.0, "h": 300.0},
        "windowFrame": {"x": 0.0, "y": 0.0, "w": 800.0, "h": 600.0}
    }))

if __name__ == '__main__':
    main()
