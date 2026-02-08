import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';

class DaemonCli {
  final String host;
  final int port;
  late WebSocketChannel channel;
  
  DaemonCli({this.host='127.0.0.1',this.port=8766});
  
  Future<void> connect() async {
    channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
    print('Connected to ws://$host:$port');
  }
  
  Future<void> status() async {
    channel.sink.add({'cmd':'status'});
    final resp = await channel.stream.first;
    final r = Map.from(resp);
    print('Status: ${r['connected'] ?? false}');
    print('Panels: ${r['activePanels'] ?? 0}');
  }
  
  Future<void> listPanels() async {
    channel.sink.add({'cmd':'list_panels'});
    final resp = await channel.stream.first;
    final panels = List.from(resp['panels'] ?? []);
    print('Panels (${panels.length}):');
    for(var p in panels){
      final marker = p['active']==true?'*':'';
      print('  $marker${p['id']} - ${p['title']}');
    }
  }
  
  Future<void> activatePanel(String id) async {
    channel.sink.add({'cmd':'activate_panel','panel_id':id});
    final resp = await channel.stream.first;
    print(resp['status']=='ok'?'OK':'Error: ${resp['error']}');
  }
  
  void close() => channel.sink.close();
}

void main(List<String> args) async {
  if(args.isEmpty){
    print('Usage: daemon_cli.dart <status|list-panels|activate-panel>');
    exit(1);
  }
  
  final cli = DaemonCli();
  await cli.connect();
  
  switch(args[0]){
    case 'status': await cli.status(); break;
    case 'list-panels': await cli.listPanels(); break;
    case 'activate-panel':
      if(args.length<2){print('Need panel id');exit(1);}
      await cli.activatePanel(args[1]);
      break;
    default:
      print('Unknown: ${args[0]}');
  }
  
  cli.close();
}
