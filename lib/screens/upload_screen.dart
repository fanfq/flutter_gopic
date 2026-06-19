import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/cloud_profile_selector.dart';
import '../app/mac_ui.dart';
import '../models/settings_model.dart';
import '../services/settings_service.dart';
import '../services/tray_service.dart';
import '../services/upload_service.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadEntry {
  _UploadEntry(this.fileName);
  final String fileName;
  double progress = 0;
  String? status; // 'done' | 'error'
  String? message;
  String? url;
}

class _UploadScreenState extends State<UploadScreen> {
  final _entries = <_UploadEntry>[];
  final _thresholdController = TextEditingController();
  final _qualityController = TextEditingController();
  bool _dragging = false;
  bool _compressionFieldsReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_compressionFieldsReady) return;
    final compression = context.read<SettingsModel>().compression;
    _thresholdController.text = _bytesToMb(compression.thresholdBytes);
    _qualityController.text = compression.quality.toString();
    _compressionFieldsReady = true;
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _qualityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final configured = settings.isConfigured;

    return MacPage(
      title: '上传',
      subtitle: '拖拽图片、选择文件，或把图片拖到状态栏图标快速上传',
      actions: [
        const CloudProfileSelector(),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _pickAndUpload,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('选择图片'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!configured) _configBanner(context),
          if (!configured) const SizedBox(height: 16),
          _compressionPanel(context),
          const SizedBox(height: 16),
          SizedBox(height: 300, child: _dropZone(context)),
          const SizedBox(height: 16),
          if (_entries.isNotEmpty) _entriesList(),
        ],
      ),
    );
  }

  Widget _configBanner(BuildContext context) {
    final active = context.watch<SettingsModel>().activeProfile;
    return MacPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  active == null
                      ? '尚未启用可用的云服务配置，请先到「设置」启用并填写参数。'
                      : '${active.name} 配置不完整，请到「设置」检查参数。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compressionPanel(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final compression = settings.compression;
    return MacPanel(
      child: Row(
        children: [
          Switch(
            value: compression.enabled,
            onChanged: (value) => _updateCompression(enabled: value),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '启用压缩',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _thresholdController,
              enabled: compression.enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '阈值 MB'),
              onSubmitted: (_) => _updateCompression(),
              onEditingComplete: _updateCompression,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _qualityController,
              enabled: compression.enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '比例 %'),
              onSubmitted: (_) => _updateCompression(),
              onEditingComplete: _updateCompression,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            compression.enabled
                ? '超过 ${_bytesToMb(compression.thresholdBytes)}MB 时按 ${compression.quality}% 处理'
                : '关闭后直接上传原图',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropZone(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        final files = details.files
            .map((f) => f.path)
            .where((p) => p.trim().isNotEmpty)
            .toList();
        if (files.isNotEmpty) _uploadAll(files);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _dragging
              ? scheme.primaryContainer.withValues(alpha: 0.45)
              : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _dragging
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.8),
            width: _dragging ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _pickAndUpload,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_upload_rounded,
                    size: 28,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _dragging ? '松开以上传' : '拖拽图片到此处，或点击选择文件',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '支持 JPG / PNG / GIF / WEBP / SVG 等',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _entriesList() {
    return MacPanel(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _entries.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final e = _entries[i];
          final done = e.status == 'done';
          final error = e.status == 'error';
          return ListTile(
            dense: true,
            leading: Icon(
              done
                  ? Icons.check_circle
                  : error
                  ? Icons.error
                  : Icons.upload_rounded,
              color: done
                  ? Colors.green
                  : error
                  ? Colors.red
                  : Theme.of(context).colorScheme.primary,
            ),
            title: Text(e.fileName, overflow: TextOverflow.ellipsis),
            subtitle: error
                ? Text(
                    e.message ?? '上传失败',
                    style: const TextStyle(color: Colors.red),
                  )
                : done
                ? Text(
                    e.url ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : LinearProgressIndicator(
                    value: e.progress == 0 ? null : e.progress,
                  ),
            trailing: done
                ? IconButton(
                    tooltip: '复制链接',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => _copy(e.url ?? ''),
                  )
                : null,
          );
        },
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    const typeGroup = XTypeGroup(
      label: 'images',
      extensions: <String>[
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'svg',
        'tif',
        'tiff',
        'ico',
        'avif',
        'heic',
      ],
    );
    final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
    if (files.isEmpty) return;
    await _uploadAll(files.map((f) => f.path).toList());
  }

  Future<void> _uploadAll(List<String> paths) async {
    final service = context.read<UploadService>();
    final trayService = context.read<TrayService>();
    for (final path in paths) {
      final name = path.split(RegExp(r'[/\\]')).last;
      final entry = _UploadEntry(name);
      setState(() => _entries.insert(0, entry));
      try {
        final result = await service.uploadFile(File(path));
        entry
          ..progress = 1
          ..status = 'done'
          ..url = result.url;
        await trayService.setLatestUpload(name, result.url);
      } catch (e) {
        entry
          ..status = 'error'
          ..message = e.toString();
      }
      if (mounted) setState(() {});
    }
    _showSnack('处理完成');
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('已复制到剪贴板');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _updateCompression({bool? enabled}) async {
    final settings = context.read<SettingsModel>();
    final current = settings.compression;
    final thresholdMb = double.tryParse(_thresholdController.text.trim()) ?? 1;
    final quality =
        int.tryParse(_qualityController.text.trim()) ?? current.quality;
    final next = current.copyWith(
      enabled: enabled,
      thresholdBytes: (thresholdMb.clamp(0.1, 1000) * 1024 * 1024).round(),
      quality: quality.clamp(1, 100),
    );
    _thresholdController.text = _bytesToMb(next.thresholdBytes);
    _qualityController.text = next.quality.toString();
    settings.setCompression(next);
    await context.read<SettingsService>().save();
  }

  String _bytesToMb(int bytes) {
    final mb = bytes / 1024 / 1024;
    return mb == mb.roundToDouble()
        ? mb.round().toString()
        : mb.toStringAsFixed(1);
  }
}
