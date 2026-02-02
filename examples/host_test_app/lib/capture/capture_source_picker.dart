import 'dart:typed_data';

import 'package:flutter/material.dart';

class CaptureSourcePicker extends StatelessWidget {
  final String title;
  final List<PickItem> items;
  final bool showSearch;

  const CaptureSourcePicker({
    super.key,
    required this.title,
    required this.items,
    this.showSearch = true,
  });

  static Future<PickItem?> show(
    BuildContext context, {
    required String title,
    required List<PickItem> items,
    bool showSearch = true,
  }) {
    return showModalBottomSheet<PickItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: CaptureSourcePicker(
            title: title,
            items: items,
            showSearch: showSearch,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    final query = ValueNotifier<String>('');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        if (showSearch)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => query.value = v,
            ),
          ),
        Flexible(
          child: ValueListenableBuilder<String>(
            valueListenable: query,
            builder: (context, q, _) {
              final needle = q.trim().toLowerCase();
              final filtered = needle.isEmpty
                  ? items
                  : items
                      .where((it) {
                        final t = it.title.toLowerCase();
                        final s = (it.subtitle ?? '').toLowerCase();
                        return t.contains(needle) || s.contains(needle);
                      })
                      .toList(growable: false);
              return ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, idx) {
                  final it = filtered[idx];
                  return ListTile(
                    leading: _Thumb(bytes: it.thumbnailBytes),
                    title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: it.subtitle == null
                        ? null
                        : Text(it.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, it),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final Uint8List? bytes;
  const _Thumb({required this.bytes});

  @override
  Widget build(BuildContext context) {
    const w = 92.0;
    const h = 52.0;
    final b = bytes;
    if (b == null || b.isEmpty) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: const Icon(Icons.crop, size: 20, color: Colors.black54),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        b,
        width: w,
        height: h,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
      ),
    );
  }
}

class PickItem {
  final String id;
  final String title;
  final String? subtitle;
  final Uint8List? thumbnailBytes;

  const PickItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnailBytes,
  });
}
