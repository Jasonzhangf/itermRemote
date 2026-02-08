#!/usr/bin/env python3
"""Log comparison tool for Host and Client debug analysis."""

import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

def parse_log_line(line: str) -> Optional[dict]:
    """Parse a JSON log line."""
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        return None

def load_logs(path: Path) -> list:
    """Load and parse log file."""
    logs = []
    if not path.exists():
        print(f"Error: {path} not found")
        return logs
    with open(path) as f:
        for line in f:
            entry = parse_log_line(line.strip())
            if entry:
                logs.append(entry)
    return logs

def main():
    host_log = Path('/tmp/itermremote_host.log')
    client_log = Path('/tmp/itermremote_client.log')
    
    print("Log Comparison Tool")
    
    host_logs = load_logs(host_log)
    client_logs = load_logs(client_log)
    
    print(f"Host logs: {len(host_logs)} entries")
    print(f"Client logs: {len(client_logs)} entries")

if __name__ == '__main__':
    main()
