import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';

/// 手势控制 mixin，支持单指移动、双指滚动/缩放
mixin GestureControllerMixin<T extends StatefulWidget> on State<T> {
  // 手势状态
  final Map<int, Offset> _pointers = {};
  final Map<int, DateTime> _pointerDownTime = {};
  final Map<int, Offset> _pointerDownPosition = {};
  Timer? _longPressTimer;
  
  Offset? _lastPosition;
  double? _lastPinchDistance;
  double? _initialPinchDistance;
  Offset? _initialTwoFingerCenter;
  
  bool _isTwoFingerScrolling = false;
  bool _isDragging = false;
  int? _draggingPointerId;
  bool _lockSingleFingerAfterTwoFinger = false;
  
  // 缩放相关
  double _videoScale = 1.0;
  Offset _videoOffset = Offset.zero;
  static const double _maxVideoScale = 5.0;
  
  // 阈值配置
  Duration get _quickTapDuration => const Duration(milliseconds: 300);
  double get _quickTapMaxDistance => 10.0;
  Duration get _longPressDuration => const Duration(milliseconds: 800);
  double get _longPressMaxDistance => 5.0;
  Duration get _twoFingerDecisionDebounce => const Duration(milliseconds: 90);
  
  // 子类需要实现的方法
  void onSingleTap(double xPercent, double yPercent);
  void onDoubleTap(double xPercent, double yPercent);
  void onPanStart(double xPercent, double yPercent);
  void onPanUpdate(double deltaX, double deltaY);
  void onPanEnd();
  void onTwoFingerScroll(double deltaX, double deltaY);
  void onPinchZoom(double scaleChange);
  
  double get videoScale => _videoScale;
  Offset get videoOffset => _videoOffset;
  
  void resetGestureState({bool lockSingleFinger = false}) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pointers.clear();
    _pointerDownTime.clear();
    _pointerDownPosition.clear();
    _lastPosition = null;
    _lastPinchDistance = null;
    _initialPinchDistance = null;
    _initialTwoFingerCenter = null;
    _isTwoFingerScrolling = false;
    _isDragging = false;
    _draggingPointerId = null;
    _lockSingleFingerAfterTwoFinger = lockSingleFinger;
  }
  
  void handlePointerDown(PointerDownEvent event, RenderBox? renderBox) {
    final localPos = renderBox?.globalToLocal(event.position);
    if (localPos == null) return;
    
    _pointers[event.pointer] = localPos;
    _pointerDownTime[event.pointer] = DateTime.now();
    _pointerDownPosition[event.pointer] = localPos;
    
    if (_pointers.length == 1) {
      _lastPosition = localPos;
      _isDragging = false;
      _draggingPointerId = null;
      _lockSingleFingerAfterTwoFinger = false;
      _startLongPressDetection(event.pointer, renderBox);
    } else if (_pointers.length == 2) {
      _lockSingleFingerAfterTwoFinger = true;
      _lastPosition = null;
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _initialPinchDistance = _calculatePinchDistance();
      _lastPinchDistance = _initialPinchDistance;
      
      final positions = _pointers.values.toList();
      _initialTwoFingerCenter = Offset(
        (positions[0].dx + positions[1].dx) / 2,
        (positions[0].dy + positions[1].dy) / 2,
      );
      _isTwoFingerScrolling = true;
    }
  }
  
  void handlePointerMove(PointerMoveEvent event, RenderBox? renderBox) {
    final localPos = renderBox?.globalToLocal(event.position);
    if (localPos == null) return;
    
    _pointers[event.pointer] = localPos;
    
    if (_pointers.length == 1) {
      if (_lockSingleFingerAfterTwoFinger) {
        _lastPosition = localPos;
        return;
      }
      if (_isDragging && _draggingPointerId == event.pointer) {
        _handleDraggingMove(localPos, renderBox);
        return;
      }
      _handleSingleFingerMove(localPos, renderBox);
    } else if (_pointers.length == 2) {
      _handleTwoFingerGesture(renderBox);
    }
  }
  
  void handlePointerUp(PointerUpEvent event, RenderBox? renderBox) {
    if (_pointers.length == 1) {
      // 单指抬起，可能是点击
      _handlePossibleTap(event.pointer, renderBox);
    }
    
    _pointers.remove(event.pointer);
    _pointerDownTime.remove(event.pointer);
    _pointerDownPosition.remove(event.pointer);
    
    if (_pointers.isEmpty) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      if (_isDragging) {
        _isDragging = false;
        _draggingPointerId = null;
        onPanEnd();
      }
      _isTwoFingerScrolling = false;
      resetGestureState();
    } else if (_pointers.length == 1) {
      // 双指变单指
      _isTwoFingerScrolling = false;
      _lastPosition = _pointers.values.first;
    }
  }
  
  void _startLongPressDetection(int pointerId, RenderBox? renderBox) {
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (!mounted) return;
      if (!_pointers.containsKey(pointerId)) return;
      if (_pointers.length != 1) return;
      
      final downPos = _pointerDownPosition[pointerId];
      final currentPos = _pointers[pointerId];
      if (downPos == null || currentPos == null) return;
      
      final distance = (currentPos - downPos).distance;
      if (distance <= _longPressMaxDistance) {
        _isDragging = true;
        _draggingPointerId = pointerId;
        final percent = _calculatePercent(currentPos, renderBox);
        if (percent != null) {
          onPanStart(percent.dx, percent.dy);
        }
      }
    });
  }
  
  void _handleSingleFingerMove(Offset position, RenderBox? renderBox) {
    if (_lastPosition == null) return;
    
    final delta = position - _lastPosition!;
    final percent = _calculatePercent(position, renderBox);
    
    if (percent != null) {
      onPanUpdate(delta.dx, delta.dy);
    }
    
    _lastPosition = position;
  }
  
  void _handleDraggingMove(Offset position, RenderBox? renderBox) {
    if (_lastPosition == null) return;
    
    final delta = position - _lastPosition!;
    onPanUpdate(delta.dx, delta.dy);
    _lastPosition = position;
  }
  
  void _handleTwoFingerGesture(RenderBox? renderBox) {
    if (_pointers.length != 2) return;
    
    final positions = _pointers.values.toList();
    final center = Offset(
      (positions[0].dx + positions[1].dx) / 2,
      (positions[0].dy + positions[1].dy) / 2,
    );
    
    final currentDistance = _calculatePinchDistance();
    if (currentDistance == 0) return;
    
    if (_lastPinchDistance != null && _lastPinchDistance! > 0) {
      final distanceChange = currentDistance / _lastPinchDistance!;
      
      // 判断是滚动还是缩放
      if (_initialPinchDistance != null) {
        final totalChange = (currentDistance - _initialPinchDistance!).abs() / _initialPinchDistance!;
        
        if (totalChange > 0.05) {
          // 缩放
          onPinchZoom(distanceChange);
        } else {
          // 滚动
          if (_lastPosition != null) {
            final delta = center - _lastPosition!;
            onTwoFingerScroll(delta.dx, delta.dy);
          }
        }
      }
    }
    
    _lastPosition = center;
    _lastPinchDistance = currentDistance;
  }
  
  void _handlePossibleTap(int pointerId, RenderBox? renderBox) {
    final downTime = _pointerDownTime[pointerId];
    final downPos = _pointerDownPosition[pointerId];
    final upPos = _pointers[pointerId];
    
    if (downTime == null || downPos == null || upPos == null) return;
    
    final duration = DateTime.now().difference(downTime);
    final distance = (upPos - downPos).distance;
    
    if (duration <= _quickTapDuration && distance <= _quickTapMaxDistance) {
      final percent = _calculatePercent(upPos, renderBox);
      if (percent != null) {
        onSingleTap(percent.dx, percent.dy);
      }
    }
  }
  
  double _calculatePinchDistance() {
    if (_pointers.length != 2) return 0.0;
    final positions = _pointers.values.toList();
    return (positions[0] - positions[1]).distance;
  }
  
  Offset? _calculatePercent(Offset localPos, RenderBox? renderBox) {
    if (renderBox == null) return null;
    final size = renderBox.size;
    if (size.width <= 0 || size.height <= 0) return null;
    return Offset(
      localPos.dx / size.width,
      localPos.dy / size.height,
    );
  }
  
  void resetTransform() {
    setState(() {
      _videoScale = 1.0;
      _videoOffset = Offset.zero;
    });
  }
  
  void setTransform(double scale, Offset offset) {
    setState(() {
      _videoScale = scale.clamp(1.0, _maxVideoScale);
      _videoOffset = offset;
    });
  }
}
