#!/bin/bash
set -e

echo "Deprecated: this script is intentionally kept as a placeholder." 
echo "We no longer run iTerm2 mock tests in CI." 
exit 0

mkdir -p scripts/python

cat > scripts/python/iterm2_sources_mock.py << 'EOF'
#!/usr/bin/env python3
import json

def main():
    panels = [
        {
            "id": "session-1",
            "title": "1.1.1",
            "detail": "bash",
            "index": 0,
            "frame": {"x": 0.0, "y": 0.0, "w": 400.0, "h": 300.0},
            "windowFrame": {"x": 0.0, "y": 0.0, "w": 800.0, "h": 600.0},
            "windowId": 1
        },
        {
            "id": "session-2",
            "title": "1.1.2",
            "detail": "python",
            "index": 1,
            "frame": {"x": 400.0, "y": 0.0, "w": 400.0, "h": 300.0},
            "windowFrame": {"x": 0.0, "y": 0.0, "w": 800.0, "h": 600.0},
            "windowId": 1
        }
    ]
    print(json.dumps({"panels": panels, "selectedSessionId": "session-1"}))

if __name__ == '__main__':
    main()
EOF

cat > scripts/python/iterm2_activate_and_crop_mock.py << 'EOF'
#!/usr/bin/env python3
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
EOF

cat > scripts/python/iterm2_send_text_mock.py << 'EOF'
#!/usr/bin/env python3
import json

def main():
    print(json.dumps({"ok": True}))

if __name__ == '__main__':
    main()
EOF

cat > scripts/python/iterm2_session_reader_mock.py << 'EOF'
#!/usr/bin/env python3
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

export ITERMREMOTE_ITERM2_MOCK=1

echo "Mock iTerm2 scripts set up"
