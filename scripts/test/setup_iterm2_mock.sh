#!/bin/bash
set -e

mkdir -p scripts/python

cat > scripts/python/iterm2_sources.py << 'EOF'
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
EOF

cat > scripts/python/iterm2_activate_and_crop.py << 'EOF'
import json
import sys

def main():
    session_id = sys.argv[1] if len(sys.argv) > 1 else ""
    print(json.dumps({
        "sessionId": session_id,
        "windowId": 12345,
        "frame": {"x": 0.0, "y": 0.0, "w": 400.0, "h": 300.0},
        "windowFrame": {"x": 0.0, "y": 0.0, "w": 800.0, "h": 600.0}
    }))

if __name__ == '__main__':
    main()
EOF

cat > scripts/python/iterm2_send_text.py << 'EOF'
import json

def main():
    print(json.dumps({"ok": True}))

if __name__ == '__main__':
    main()
EOF

cat > scripts/python/iterm2_session_reader.py << 'EOF'
import base64
import json
import sys

def main():
    session_id = sys.argv[1] if len(sys.argv) > 1 else ""
    content = f"Mock session buffer for {session_id}\n$ "
    text_b64 = base64.b64encode(content.encode("utf-8")).decode("ascii")
    print(json.dumps({"text": text_b64}))

if __name__ == '__main__':
    main()
EOF

chmod +x scripts/python/*.py || true

echo "Mock iTerm2 scripts set up"

