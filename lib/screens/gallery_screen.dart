import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:provider/provider.dart';

import '../app/cloud_profile_selector.dart';
import '../app/mac_ui.dart';
import '../models/history_model.dart';
import '../models/cloud_model.dart';
import '../services/history_service.dart';
import '../utils/format.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  String _extension = '';
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryModel>();
    final activeProfile = context.watch<CloudModel>().activeProfile;
    final extensions = history.extensionsForProfile(activeProfile?.id);
    final items = history.itemsForProfileAndExtension(
      activeProfile?.id,
      _extension,
    );
    _selectedIds.removeWhere(
      (id) => !history.items.any((item) => item.id == id),
    );

    return MacPage(
      title: '图床',
      subtitle: activeProfile == null
          ? '请选择已启用的云服务配置'
          : (items.isEmpty
                ? '${activeProfile.name} 暂无上传记录'
                : '${activeProfile.name} · 共 ${items.length} 张图片'),
      actions: [
        const CloudProfileSelector(),
        if (extensions.isNotEmpty) ...[
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _extension,
            items: [
              const DropdownMenuItem(value: '', child: Text('全部')),
              for (final extension in extensions)
                DropdownMenuItem(value: extension, child: Text('.$extension')),
            ],
            onChanged: (value) => setState(() {
              _extension = value ?? '';
              _selectedIds.clear();
            }),
          ),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(width: 10),
          IconButton(
            tooltip: _selectedIds.length == items.length ? '取消全选' : '全选',
            icon: Icon(
              _selectedIds.length == items.length
                  ? Icons.deselect
                  : Icons.select_all,
            ),
            onPressed: () => setState(() {
              if (_selectedIds.length == items.length) {
                _selectedIds.clear();
              } else {
                _selectedIds.addAll(items.map((item) => item.id));
              }
            }),
          ),
          IconButton(
            tooltip: '清空历史',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClear(context),
          ),
        ],
      ],
      maxWidth: 1180,
      child: Column(
        children: [
          if (_selectedIds.isNotEmpty) _batchBar(context),
          items.isEmpty
              ? SizedBox(
                  height: 420,
                  child: _EmptyState(
                    message: activeProfile == null ? '未选择云服务配置' : '当前配置还没有上传记录',
                  ),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 210,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _GalleryCard(
                    item: items[i],
                    selected: _selectedIds.contains(items[i].id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selectedIds.add(items[i].id);
                      } else {
                        _selectedIds.remove(items[i].id);
                      }
                    }),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('将删除当前云服务配置下的历史记录和本地缓存，已上传到云端的文件不会被删除。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final profileId = context.read<CloudModel>().activeProfile?.id;
      if (profileId != null) {
        await context.read<HistoryService>().clearProfile(profileId);
      }
    }
  }

  Widget _batchBar(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: MacPanel(
      child: Row(
        children: [
          Text('已选 ${_selectedIds.length} 项'),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _exportSelected,
            icon: const Icon(Icons.folder_outlined),
            label: const Text('导出到目录'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _removeSelected,
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除本地记录'),
          ),
        ],
      ),
    ),
  );

  Future<void> _exportSelected() async {
    final path = await getDirectoryPath();
    if (path == null || !mounted) return;
    final result = await context.read<HistoryService>().exportCachedFiles(
      ids: _selectedIds,
      destination: Directory(path),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出 ${result.exported} 项${result.failed == 0 ? '' : '，${result.failed} 项失败'}',
          ),
        ),
      );
    }
  }

  Future<void> _removeSelected() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除本地记录'),
        content: const Text('仅删除本地上传历史和缓存，不会删除云端文件。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<HistoryService>().removeMany(_selectedIds);
      if (mounted) setState(_selectedIds.clear);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.photo_library_outlined,
              size: 30,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '上传图片后可复制链接、Markdown 或删除记录',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.item,
    required this.selected,
    required this.onSelected,
  });
  final HistoryItem item;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _preview(context),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumb(context),
                  Positioned(
                    left: 5,
                    top: 5,
                    child: Checkbox(
                      value: selected,
                      onChanged: (value) => onSelected(value ?? false),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(
                          Icons.zoom_out_map_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${formatBytes(item.sizeBytes)} · ${formatDateTime(item.uploadedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (v) => _onMenu(context, v),
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'copy_url', child: Text('复制链接')),
                    PopupMenuItem(value: 'copy_md', child: Text('复制 Markdown')),
                    PopupMenuItem(
                      value: 'copy_md_mini',
                      child: Text('复制缩略 Markdown'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('删除记录')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(BuildContext context) {
    if (item.localThumbPath != null &&
        File(item.localThumbPath!).existsSync()) {
      return Image.file(
        File(item.localThumbPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
      );
    }
    if (item.contentType.startsWith('image/')) {
      return Image.network(
        item.url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Icon(
      Icons.image_outlined,
      size: 40,
      color: Theme.of(context).colorScheme.outline,
    ),
  );

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        key: const ValueKey('image-preview-dialog'),
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '复制链接',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => _copy(context, item.url),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: _previewImage(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewImage(BuildContext context) {
    if (item.localThumbPath != null &&
        File(item.localThumbPath!).existsSync()) {
      return Image.file(
        File(item.localThumbPath!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
      );
    }
    return Image.network(
      item.url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _placeholder(context),
    );
  }

  void _onMenu(BuildContext context, String action) {
    switch (action) {
      case 'copy_url':
        _copy(context, item.url);
        break;
      case 'copy_md':
        _copy(context, '![${item.fileName}](${item.url})');
        break;
      case 'copy_md_mini':
        _copy(context, '![${item.fileName}](${item.url} "${item.fileName}")');
        break;
      case 'delete':
        _delete(context);
        break;
    }
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  Future<void> _delete(BuildContext context) async {
    await context.read<HistoryService>().remove(item.id);
  }
}
