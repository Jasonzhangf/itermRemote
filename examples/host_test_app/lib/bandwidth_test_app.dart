import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:iterm2_host/webrtc/encoding_policy/encoding_policy.dart';

/// 带宽编码矩阵测试应用
///
/// 用于测试不同 FPS 和码率组合下的编码效果
/// 运行: flutter run -d macos lib/bandwidth_test_app.dart
void main() {
  runApp(const MaterialApp(home: BandwidthTestApp()));
}

class BandwidthTestApp extends StatefulWidget {
  const BandwidthTestApp({super.key});

  @override
  State<BandwidthTestApp> createState() => _BandwidthTestAppState();
}

class _BandwidthTestAppState extends State<BandwidthTestApp> {
  // WebRTC
  late RTCPeerConnection _pc1;
  late RTCPeerConnection _pc2;
  RTCRtpSender? _sender;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _captureStream;

  // 测试矩阵
  final List<int> _fpsList = [60, 30, 15];
  final List<int> _bitrateKbpsList = [80, 125, 250, 500, 1000, 2000];
  late final List<_TestCase> _testCases;
  int _currentCaseIndex = 0;

  // 策略配置
  EncodingProfile _selectedProfile = EncodingProfiles.textLatency;

  // 统计数据
  Map<String, dynamic> _txStats = {};
  Map<String, dynamic> _rxStats = {};
  Timer? _statsTimer;
  int _statsSampleCount = 0;
  double _avgBitrateKbps = 0;
  double _avgFps = 0;
  double _avgPacketsLost = 0;

  // 状态
  bool _isReady = false;
  bool _isTesting = false;
  String _statusMessage = '准备中...';

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();
    _generateTestCases();
    _initWebRTC();
  }

  void _generateTestCases() {
    _testCases = [];
    for (final fps in _fpsList) {
      for (final bitrate in _bitrateKbpsList) {
        _testCases.add(_TestCase(fps: fps, bitrateKbps: bitrate));
      }
    }
    // 按码率从低到高排序，便于渐进式测试
    _testCases.sort((a, b) => a.bitrateKbps.compareTo(b.bitrateKbps));
  }

  Future<void> _initWebRTC() async {
    try {
      // 1. 创建屏幕捕获流
      final mediaConstraints = <String, dynamic>{
        'audio': false,
        'video': {'frameRate': 60.0}, // 最高帧率捕获
      };

      _captureStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      _localRenderer.srcObject = _captureStream;

      // 2. 创建两个 PeerConnection (Loopback)
      final configuration = <String, dynamic>{
        'iceServers': [], // 本地测试，不需要 STUN/TURN
      };

      _pc1 = await createPeerConnection(configuration);
      _pc2 = await createPeerConnection(configuration);

      // ICE 交换
      _pc1.onIceCandidate = (candidate) => _pc2.addCandidate(candidate);
      _pc2.onIceCandidate = (candidate) => _pc1.addCandidate(candidate);

      // 接收端显示
      _pc2.onAddStream = (stream) {
        _remoteRenderer.srcObject = stream;
      };

      // 添加轨道
      final videoTrack = _captureStream!.getVideoTracks().first;
      _sender = await _pc1.addTrack(videoTrack, _captureStream!);

      // 创建 Offer/Answer
      final offer = await _pc1.createOffer();
      await _pc1.setLocalDescription(offer);
      await _pc2.setRemoteDescription(offer);

      final answer = await _pc2.createAnswer();
      await _pc2.setLocalDescription(answer);
      await _pc1.setRemoteDescription(answer);

      setState(() {
        _isReady = true;
        _statusMessage = '就绪 - 共 ${_testCases.length} 个测试用例';
      });

      // 启动统计采样
      _startStatsCollection();
    } catch (e) {
      setState(() => _statusMessage = '初始化失败: $e');
    }
  }

  void _startStatsCollection() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_sender == null) return;

      final txReport = await _sender!.getStats();
      for (final stat in txReport) {
        if (stat.type == 'outbound-rtp' && stat.values['kind'] == 'video') {
          setState(() {
            _txStats = Map<String, dynamic>.from(stat.values);
          });
        }
      }

      final rxReport = await _pc2.getStats();
      for (final stat in rxReport) {
        if (stat.type == 'inbound-rtp' && stat.values['kind'] == 'video') {
          setState(() {
            _rxStats = Map<String, dynamic>.from(stat.values);
          });
        }
      }

      if (_isTesting) {
        _statsSampleCount++;
        _avgBitrateKbps += (_txStats['bytesSent'] ?? 0) * 8 / 1000;
        _avgFps += _txStats['framesEncoded'] ?? 0;
        _avgPacketsLost += _rxStats['packetsLost'] ?? 0;
      }
    });
  }

  Future<void> _applyTestCase(_TestCase testCase) async {
    if (_sender == null) return;

    final params = _sender!.parameters;
    if (params.encodings == null || params.encodings!.isEmpty) {
      params.encodings = [RTCRtpEncoding()];
    }

    final encoding = params.encodings!.first;
    encoding.maxBitrate = testCase.bitrateKbps * 1000;
    encoding.maxFramerate = testCase.fps;
    encoding.scaleResolutionDownBy = 1.0;

    // 根据选择的 profile 设置 degradationPreference
    final pref = _getDegradationPreference(_selectedProfile);
    params.degradationPreference = pref;

    await _sender!.setParameters(params);

    // 重置统计
    _statsSampleCount = 0;
    _avgBitrateKbps = 0;
    _avgFps = 0;
    _avgPacketsLost = 0;
  }

  RTCDegradationPreference _getDegradationPreference(EncodingProfile profile) {
    switch (profile.id) {
      case 'text_latency':
        return RTCDegradationPreference.MAINTAIN_FRAMERATE;
      case 'text_quality':
        return RTCDegradationPreference.MAINTAIN_RESOLUTION;
      case 'balanced':
        return RTCDegradationPreference.BALANCED;
      default:
        return RTCDegradationPreference.BALANCED;
    }
  }

  Future<void> _runNextCase() async {
    if (_currentCaseIndex >= _testCases.length) {
      setState(() {
        _statusMessage = '测试完成！';
        _isTesting = false;
      });
      return;
    }

    final testCase = _testCases[_currentCaseIndex];
    await _applyTestCase(testCase);

    setState(() {
      _statusMessage = '测试 ${_currentCaseIndex + 1}/${_testCases.length}: '
                      '${testCase.fps} FPS @ ${testCase.bitrateKbps} kbps';
      _isTesting = true;
    });

    // 等待 5 秒收集数据
    await Future.delayed(const Duration(seconds: 5));

    _currentCaseIndex++;
    _runNextCase();
  }

  void _resetTest() {
    _currentCaseIndex = 0;
    _statsSampleCount = 0;
    _avgBitrateKbps = 0;
    _avgFps = 0;
    _avgPacketsLost = 0;
    setState(() {
      _statusMessage = '已重置';
      _isTesting = false;
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _pc1.close();
    _pc2.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentCase = _currentCaseIndex < _testCases.length
        ? _testCases[_currentCaseIndex]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('iTerm2 带宽编码矩阵测试'),
        actions: [
          DropdownButton<EncodingProfile>(
            value: _selectedProfile,
            items: EncodingProfiles.all.map((p) {
              return DropdownMenuItem(
                value: p,
                child: Text(p.name),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedProfile = v);
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // 左侧控制面板
          SizedBox(
            width: 350,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildControlCard(),
                const SizedBox(height: 16),
                _buildCurrentCaseCard(currentCase),
                const SizedBox(height: 16),
                _buildStatsCard(),
                const SizedBox(height: 16),
                _buildTestMatrixCard(),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // 右侧视频预览
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildVideoCard('本地捕获', _localRenderer),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _buildVideoCard('编码后 (Loopback)', _remoteRenderer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_statusMessage),
            if (!_isReady)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _isReady && !_isTesting ? _runNextCase : null,
              child: const Text('开始测试 / 下一个'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isTesting ? null : _resetTest,
              child: const Text('重置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentCaseCard(_TestCase? testCase) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前测试用例',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (testCase != null) ...[
              Text('FPS: ${testCase.fps}'),
              Text('码率: ${testCase.bitrateKbps} kbps'),
            ] else
              const Text('无'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('实时统计', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('采样数: $_statsSampleCount'),
            if (_statsSampleCount > 0) ...[
              Text('平均码率: ${(_avgBitrateKbps / _statsSampleCount).toStringAsFixed(1)} kbps'),
              Text('平均FPS: ${(_avgFps / _statsSampleCount).toStringAsFixed(1)}'),
              Text('平均丢包: ${(_avgPacketsLost / _statsSampleCount).toStringAsFixed(1)}'),
            ],
            const Divider(),
            Text('发送端统计:', style: Theme.of(context).textTheme.titleSmall),
            Text('帧高: ${_txStats['frameHeight'] ?? 'N/A'}'),
            Text('帧宽: ${_txStats['frameWidth'] ?? 'N/A'}'),
            Text('编码帧数: ${_txStats['framesEncoded'] ?? 'N/A'}'),
            Text('发送字节: ${_txStats['bytesSent'] ?? 'N/A'}'),
            const Divider(),
            Text('接收端统计:', style: Theme.of(context).textTheme.titleSmall),
            Text('解码帧数: ${_rxStats['framesDecoded'] ?? 'N/A'}'),
            Text('丢包数: ${_rxStats['packetsLost'] ?? 'N/A'}'),
            Text(
              '丢包率: ${_rxStats['packetsLost'] != null && _rxStats['packetsReceived'] != null
                  ? (((_rxStats['packetsLost']! /
                              (_rxStats['packetsLost']! + _rxStats['packetsReceived']!)) *
                          100)
                      .toStringAsFixed(2) +
                      '%')
                  : 'N/A'}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestMatrixCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('测试矩阵 (${_testCases.length} 个用例)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('FPS: ${_fpsList.join(', ')}'),
            Text('码率: ${_bitrateKbpsList.join(', ')} kbps'),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(String title, RTCVideoRenderer renderer) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: RTCVideoView(renderer),
        ),
      ],
    );
  }
}

class _TestCase {
  final int fps;
  final int bitrateKbps;

  _TestCase({required this.fps, required this.bitrateKbps});

  @override
  String toString() => '$fps FPS @ $bitrateKbps kbps';
}
