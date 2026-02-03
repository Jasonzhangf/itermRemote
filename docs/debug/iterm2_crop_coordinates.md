# iTerm2 Panel 裁切坐标问题分析

## 问题发现时间
2026-02-03 21:22 UTC+8

## 问题现象
host_test_app 的 iTerm2 panel 视频编码裁切宽高完全不对，红框 overlay 显示的裁切区域和实际 panel 边界不匹配。

## 根本原因

### 1. iTerm2 Frame 坐标系是 bottom-left，不是 top-left

**官方文档确认**（来源：iTerm2 Python API - Frame Class）：
```
class Frame(origin: iterm2.util.Point = (0, 0), size: iterm2.util.Size = ...)
  Describes a bounding rectangle.
  0,0 is the bottom left coordinate.  👈 关键！
```

- iTerm2 的 `Frame` 类坐标原点 (0,0) 是 **bottom-left（左下角）**
- 我们的 overlay 脚本假设 (0,0) 是 **top-left（左上角）**
- **导致 y 坐标完全错误**

### 2. Session.frame 不是真实的像素坐标

通过查阅 iTerm2 Python API 文档和实测发现：
- `Session` 对象**没有 `async_get_frame()` 或 `.frame` 属性**
- 只有 `grid_size` 属性（返回字符单元格尺寸）
- 我们现在拿到的 `frame: {x: 0, y: 0, w: 675, h: 979}` 是**从 splitter tree 推断**出来的（通过 `assign_layout_frames` 函数）
- **推断的坐标和实际 panel 像素尺寸不一致**

### 3. 多个坐标系混用导致宽高错误

当前代码中同时存在多个坐标系：

| 坐标系 | 来源 | 尺寸示例 | 说明 |
|--------|------|----------|------|
| `frame` | splitter tree 推断 | (0, 0, 675, 979) | 推断的 panel 坐标 |
| `windowFrame` | iTerm2 API | (0, 0, 1381, 1978) | 窗口内容区域（可能是 point 坐标） |
| `rawWindowFrame` | Quartz API | (0, 84, 3840, 2046) | 窗口像素坐标（包含标题栏，y=84） |
| `layoutFrame` | splitter tree 推断 | (0, 0, 675, 979) | 推断的 panel 坐标 |
| `layoutWindowFrame` | splitter tree 推断 | (0, 0, 3836, 1977) | 推断的窗口内容区域 |
| `screencapture -l` 输出 | macOS 截图 | 3908 x 2114 | 实际捕获的图片尺寸 |

**问题**：
- `screencapture -l` 输出尺寸 (3908 x 2114) 和任何一个 Frame 都不完全匹配
- 缩放因子不是 1:1：
  - 宽度：3908 / 3836 = **1.019**
  - 高度：2114 / 1977 = **1.069**

## 正确的修复方案

### 方案 1：修正 overlay 坐标系转换（立即修复）✅

在 overlay 脚本中：
1. 将 iTerm2 的 bottom-left 坐标转换成图片的 top-left 坐标
2. y 坐标翻转：`y_top_left = imageHeight - y_bottom_left - height`
3. 考虑 screencapture 实际输出尺寸和 layoutWindowFrame 的缩放差异

**代码示例**：
```python
# 读取实际图片尺寸
img = Image.open(window_path)
img_w, img_h = img.size

# iTerm2 layoutFrame (bottom-left origin)
lf_x, lf_y, lf_w, lf_h = ...
lww, lwh = 3836.0, 1977.0  # layoutWindowFrame

# 转换到 top-left 坐标系
y_top_left = lwh - lf_y - lf_h

# 归一化到实际图片尺寸
x_norm = lf_x / lww
y_norm = y_top_left / lwh
w_norm = lf_w / lww
h_norm = lf_h / lwh

# 计算实际像素坐标
left = int(round(x_norm * img_w))
top = int(round(y_norm * img_h))
right = int(round((x_norm + w_norm) * img_w))
bottom = int(round((y_norm + h_norm) * img_h))
```

### 方案 2：使用真实的第一帧作为 window_capture（更可靠）🎯

不用 `screencapture -l`，而是：
1. 直接保存 SCK 捕获的第一帧作为 `window_capture.png`
2. 这样 window_capture.png 和编码裁切使用**完全相同的坐标系**
3. 红框和裁切永远对齐
4. 避免 screencapture 和 SCK 的坐标系差异

**优势**：
- 坐标系统一，不需要复杂的转换
- window_capture.png 就是实际编码的源图像
- overlay 红框直接用 cropRectNorm 即可，无需任何转换

### 方案 3：获取真实的 panel 像素坐标（长期方案）🔬

研究如何从 iTerm2 获取真实的 panel 像素坐标：

**可能的方法**：
1. 通过 `grid_size` 和字体大小计算像素尺寸
   ```python
   grid_size = session.grid_size  # 字符单元格尺寸
   # 需要获取字体像素大小
   ```

2. 用 macOS Accessibility API 获取真实边界
   - 通过 CGWindowID 获取窗口信息
   - 用 Quartz 获取每个 pane 的实际边界

3. 用 tmux 命令获取 pane 坐标（如果 iTerm2 运行在 tmux 中）
   ```bash
   tmux list-panes -F "#{pane_left} #{pane_top} #{pane_width} #{pane_height}"
   ```

## 验证方法

修复后需要验证：
1. 红框位置和 iTerm2 split 分割线完全对齐
2. 红框宽高和 panel 实际边界完全一致
3. 多个不同大小的 panel 都能正确裁切

**验证脚本**：
```bash
ITERM2_PANEL_TITLE=1.1.1 FPS_LIST=30 BITRATE_KBPS_LIST=1500 \
  bash scripts/test/run_iterm2_panel_encoding_matrix.sh
# 检查 window_with_crop.png，红框应精确对齐 panel 边界
```

## 参考资料

- [iTerm2 Python API - Frame Class](https://iterm2.com/python-api/util.html#iterm2.util.Frame)
- [iTerm2 Python API - Session](https://iterm2.com/python-api/session.html)
- [iTerm2 Python API - Window](https://iterm2.com/python-api/window.html)

## 下一步行动

按优先级：
1. ✅ 立即修复：实现方案 1（overlay 坐标系转换）
2. 🎯 验证：用实际 iTerm2 窗口测试，确保红框对齐
3. 🔧 优化：实现方案 2（用 SCK 第一帧作为 window_capture）
4. 🔬 研究：方案 3（获取真实 panel 像素坐标）

## 额外发现：编码尺寸会被对齐到 16 的倍数

在 flutter-webrtc 的 macOS ScreenCaptureKit 路径里（`plugins/flutter-webrtc/.../FlutterRTCDesktopCapturer.m`），
为了硬件编码稳定性，会把裁切后的宽高对齐到 16 的倍数（并做 clamp）。

这会导致：
- iTerm2 pane 实际尺寸比如 675x979
- 编码/解码统计里显示的帧尺寸可能是 672x976 或类似（对齐后的值）

验证时应以：
1) 红框是否贴合 panel 边界（几像素误差可接受）
2) WebRTC inbound/outbound frameWidth/Height 是否接近（并考虑 16 对齐）
为准。
