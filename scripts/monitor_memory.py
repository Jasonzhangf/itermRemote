#!/usr/bin/env python3
"""
Memory monitoring daemon for iTermRemote host processes.

Usage:
    # Foreground (for launchd/system service)
    python3 scripts/monitor_memory.py run --target host_test_app --interval 5 --threshold 2048

    # Background daemon (manual)
    python3 scripts/monitor_memory.py start --target host_test_app --interval 5 --threshold 2048
    python3 scripts/monitor_memory.py stop
    python3 scripts/monitor_memory.py status

Logs are written to: build/memory_monitor.log
"""

import argparse
import os
import signal
import sys
import time
from pathlib import Path
from datetime import datetime
from typing import Optional
import psutil

PID_FILE = Path("build/.memory_monitor.pid")
LOG_FILE = Path("build/memory_monitor.log")


def set_state_dir(state_dir: Optional[str]) -> None:
    """Set pid/log file locations based on state directory."""
    global PID_FILE, LOG_FILE
    if state_dir:
        base = Path(state_dir)
    else:
        env = os.environ.get("ITERMREMOTE_MONITOR_STATE_DIR")
        base = Path(env) if env else Path("build")
    PID_FILE = base / ".memory_monitor.pid"
    LOG_FILE = base / "memory_monitor.log"


def find_process(target: str):
    """Find process by name (bundle or executable)."""
    for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'create_time']):
        try:
            name = proc.info['name'] or ''
            cmdline = ' '.join(proc.info['cmdline'] or [])
            # Match by name or full path
            if target.lower() in name.lower() or target.lower() in cmdline.lower():
                return proc
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return None


def log_message(msg: str):
    """Write message to log file with timestamp."""
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {msg}\n"
    with open(LOG_FILE, 'a') as f:
        f.write(line)
    print(line, end='')


def monitor_loop(target: str, interval: int, threshold_mb: int):
    """Main monitoring loop."""
    log_message(f"Started monitoring: target={target} interval={interval}s threshold={threshold_mb}MB")
    
    last_rss = None
    alert_count = 0
    MAX_ALERTS = 3  # Alert every N samples instead of every sample
    
    while True:
        proc = find_process(target)
        if proc:
            try:
                mem = proc.memory_info()
                rss_mb = mem.rss / (1024 * 1024)
                
                # Calculate delta
                delta = 0.0
                if last_rss is not None:
                    delta = rss_mb - last_rss
                
                # Log sample
                status = ""
                if rss_mb > threshold_mb:
                    alert_count += 1
                    if alert_count % MAX_ALERTS == 0:
                        status = " [ALERT: HIGH MEMORY]"
                        log_message(f"{target} RSS={rss_mb:.1f}MB (delta={delta:+.1f}MB){status}")
                else:
                    alert_count = 0
                    # Only log when there's significant change or periodically
                    if abs(delta) > 10.0 or alert_count % 10 == 0:
                        log_message(f"{target} RSS={rss_mb:.1f}MB (delta={delta:+.1f}MB)")
                
                last_rss = rss_mb
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                log_message(f"{target} process disappeared, will retry...")
                last_rss = None
        else:
            log_message(f"{target} not found, waiting...")
            last_rss = None
        
        time.sleep(interval)


def start_daemon(target: str, interval: int, threshold_mb: int):
    """Start the daemon in background."""
    if PID_FILE.exists():
        pid = int(PID_FILE.read_text().strip())
        try:
            os.kill(pid, 0)
            print(f"Daemon already running (PID {pid})")
            return
        except OSError:
            PID_FILE.unlink()
    
    pid = os.fork()
    if pid > 0:
        # Parent: save PID and exit
        PID_FILE.parent.mkdir(parents=True, exist_ok=True)
        PID_FILE.write_text(str(pid))
        print(f"Daemon started (PID {pid})")
        print(f"Logging to: {LOG_FILE.absolute()}")
        return
    
    # Child: daemonize
    os.setsid()
    os.umask(0)
    
    # Redirect stdin/stdout/stderr to devnull
    with open(os.devnull, 'r') as devnull_r:
        os.dup2(devnull_r.fileno(), 0)
    with open(os.devnull, 'w') as devnull_w:
        os.dup2(devnull_w.fileno(), 1)
        os.dup2(devnull_w.fileno(), 2)

    # Single fork is enough; keep PID stable for stop/status.
    try:
        monitor_loop(target, interval, threshold_mb)
    except KeyboardInterrupt:
        log_message("Daemon stopped (interrupted)")
        PID_FILE.unlink(missing_ok=True)
    except Exception as e:
        log_message(f"Daemon error: {e}")
        PID_FILE.unlink(missing_ok=True)


def stop_daemon():
    """Stop the daemon."""
    if not PID_FILE.exists():
        print("Daemon not running")
        return
    
    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, signal.SIGTERM)
        # Wait for it to exit
        for _ in range(10):
            try:
                os.kill(pid, 0)
                time.sleep(0.1)
            except OSError:
                break
        else:
            os.kill(pid, signal.SIGKILL)
        
        PID_FILE.unlink()
        print(f"Daemon stopped (PID {pid})")
    except (ValueError, ProcessLookupError) as e:
        print(f"Error stopping daemon: {e}")
        PID_FILE.unlink(missing_ok=True)


def show_status():
    """Show daemon status and recent logs."""
    if not PID_FILE.exists():
        print("Daemon not running")
        return
    
    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, 0)
        print(f"Daemon running (PID {pid})")
    except OSError:
        print("Daemon PID file exists but process not found")
        PID_FILE.unlink()
        return
    
    print(f"\nRecent logs ({LOG_FILE.absolute()}):")
    if LOG_FILE.exists():
        lines = LOG_FILE.read_text().splitlines()
        for line in lines[-20:]:
            print(f"  {line}")
    else:
        print("  No logs yet")


def run_foreground(target: str, interval: int, threshold_mb: int):
    """Run monitor loop in the foreground (for launchd/system service)."""
    try:
        monitor_loop(target, interval, threshold_mb)
    except KeyboardInterrupt:
        log_message("Monitor stopped (interrupted)")
    except Exception as e:
        log_message(f"Monitor error: {e}")


def main():
    parser = argparse.ArgumentParser(description="Memory monitoring daemon")
    parser.add_argument(
        '--state-dir',
        default=None,
        help='Directory to store pid/log files (default: env ITERMREMOTE_MONITOR_STATE_DIR or ./build)',
    )
    subparsers = parser.add_subparsers(dest='command', help='Command')
    
    run_cmd = subparsers.add_parser('run', help='Run in foreground (system service)')
    run_cmd.add_argument('--target', default='host_test_app', help='Process name to monitor')
    run_cmd.add_argument('--interval', type=int, default=5, help='Sampling interval (seconds)')
    run_cmd.add_argument('--threshold', type=int, default=2048, help='Alert threshold (MB)')

    start_cmd = subparsers.add_parser('start', help='Start monitoring')
    start_cmd.add_argument('--target', default='host_test_app', help='Process name to monitor')
    start_cmd.add_argument('--interval', type=int, default=5, help='Sampling interval (seconds)')
    start_cmd.add_argument('--threshold', type=int, default=2048, help='Alert threshold (MB)')
    
    subparsers.add_parser('stop', help='Stop monitoring')
    subparsers.add_parser('status', help='Show status and recent logs')
    
    args = parser.parse_args()

    set_state_dir(args.state_dir)
    
    if args.command == 'run':
        run_foreground(args.target, args.interval, args.threshold)
    elif args.command == 'start':
        start_daemon(args.target, args.interval, args.threshold)
    elif args.command == 'stop':
        stop_daemon()
    elif args.command == 'status':
        show_status()
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
