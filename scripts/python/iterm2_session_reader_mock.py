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
