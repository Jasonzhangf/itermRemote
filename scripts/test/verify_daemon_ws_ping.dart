import "dart:convert";
import "dart:io";

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args.first : "ws://127.0.0.1:8766";
  final ws = await WebSocket.connect(url);

  final id = "ping-${DateTime.now().millisecondsSinceEpoch}";
  ws.add(jsonEncode({
    "version": 1,
    "type": "cmd",
    "id": id,
    "target": "echo",
    "action": "echo",
    "payload": {"hello": "world"},
  }));

  await for (final msg in ws) {
    if (msg is! String) continue;
    final m = jsonDecode(msg);
    if (m is Map && m["type"] == "ack" && m["id"] == id) {
      stdout.writeln(msg);
      await ws.close();
      exit(0);
    }
  }
  await ws.close();
  exit(2);
}
