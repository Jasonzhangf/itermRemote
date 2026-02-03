import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class RunLogger {
  final String runId;
  final Directory dir;
  final File logFile;

  RunLogger._(this.runId, this.dir, this.logFile);

  static Future<RunLogger> create({required String appName}) async {
    final base = (Platform.environment['ITERMREMOTE_LOG_DIR'] ?? '').trim();
    final root = base.isEmpty ? '/tmp/itermremote_logs' : base;
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final runId = '$appName-$ts-${_pid()}';
    final dir = Directory('$root/$appName/$runId');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final logFile = File('${dir.path}/run.log');
    logFile.writeAsStringSync('');
    final logger = RunLogger._(runId, dir, logFile);
    logger.log('run_id=$runId');
    logger.log('pid=${_pid()}');
    logger.log('cwd=${Directory.current.path}');
    logger.log('env_log_dir=${base.isEmpty ? '(default)' : base}');
    return logger;
  }

  void log(String message) {
    final ts = DateTime.now().toIso8601String();
    logFile.writeAsStringSync('[$ts] $message\n', mode: FileMode.append);
  }

  void logJson(String label, Map<String, dynamic> data) {
    final payload = jsonEncode(data);
    log('$label $payload');
  }

  File writeJson(String name, Map<String, dynamic> data) {
    final path = '${dir.path}/$name.json';
    File(
      path,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    log('write_json name=$name path=$path');
    return File(path);
  }

  File writePng(String name, Uint8List bytes) {
    final path = '${dir.path}/$name.png';
    File(path).writeAsBytesSync(bytes);
    log('write_png name=$name path=$path bytes=${bytes.length}');
    return File(path);
  }

  void logError(Object error, StackTrace stack) {
    log('ERROR $error');
    log(stack.toString());
  }

  static int _pid() => pid;
}
