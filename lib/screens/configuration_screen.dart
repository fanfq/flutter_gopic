import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/mac_ui.dart';
import '../models/cloud_model.dart';
import '../services/cloud_service.dart';
import '../services/history_service.dart';
import '../services/launch_at_login_service.dart';
import '../utils/format.dart';

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key});

  static const _jsonTypeGroup = XTypeGroup(
    label: 'JSON configuration',
    extensions: ['json'],
  );

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  late Future<CacheSummary> _cacheSummary;
  late final LaunchAtLoginService _launchAtLoginService;
  bool? _launchAtLoginEnabled;
  var _launchAtLoginAvailable = true;
  var _isUpdatingLaunchAtLogin = false;

  @override
  void initState() {
    super.initState();
    _cacheSummary = context.read<HistoryService>().cacheSummary();
    _launchAtLoginService = LaunchAtLoginService();
    _loadLaunchAtLoginState();
  }

  Future<void> _loadLaunchAtLoginState() async {
    try {
      final enabled = await _launchAtLoginService.isEnabled();
      if (!mounted) return;
      setState(() => _launchAtLoginEnabled = enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _launchAtLoginEnabled = false;
        _launchAtLoginAvailable = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudModel>();
    return MacPage(
      title: '配置',
      subtitle: '上传命名与云服务配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MacSectionTitle('开机自启动'),
          MacPanel(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('登录后自动启动 GoPic'),
              subtitle: Text(
                !_launchAtLoginAvailable
                    ? '当前 macOS 环境无法设置开机自启动'
                    : _launchAtLoginEnabled == null
                    ? '正在读取系统状态…'
                    : '电脑重启并登录当前账户后，自动启动 GoPic',
              ),
              value: _launchAtLoginEnabled ?? false,
              onChanged:
                  !_launchAtLoginAvailable ||
                      _launchAtLoginEnabled == null ||
                      _isUpdatingLaunchAtLogin
                  ? null
                  : _setLaunchAtLogin,
            ),
          ),
          const SizedBox(height: 24),
          MacSectionTitle('上传文件重命名'),
          MacPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '后续上传的文件将按所选规则命名。UUID 规则不会包含原文件名。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<UploadNamingPattern>(
                  initialValue: cloud.uploadNamingPattern,
                  decoration: const InputDecoration(labelText: '重命名方案'),
                  items: [
                    for (final pattern in UploadNamingPattern.values)
                      DropdownMenuItem(
                        value: pattern,
                        child: Text(pattern.label),
                      ),
                  ],
                  onChanged: (pattern) async {
                    if (pattern == null) {
                      return;
                    }
                    cloud.setUploadNamingPattern(pattern);
                    await context.read<CloudService>().save();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          MacSectionTitle('图床缓存'),
          MacPanel(
            child: FutureBuilder<CacheSummary>(
              future: _cacheSummary,
              builder: (context, snapshot) {
                final summary = snapshot.data;
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting;
                final description = isLoading
                    ? '正在统计本地缓存…'
                    : summary == null
                    ? '无法读取本地缓存'
                    : '共 ${summary.fileCount} 个文件，占用 ${formatBytes(summary.totalBytes)}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '缓存目录：${summary.directoryPath}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: summary == null
                              ? null
                              : () => _confirmClearCache(summary),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清除本地缓存'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _confirmClearHistory,
                          icon: const Icon(Icons.history_toggle_off_outlined),
                          label: const Text('清除上传历史'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          MacSectionTitle('导出配置'),
          MacPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '将当前所有云服务配置导出为 JSON 文件，便于备份或迁移。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '文件包含明文密钥，请妥善保管',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _exportConfiguration(context),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('导出配置'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          MacSectionTitle('导入配置'),
          MacPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导入 JSON 配置后，所有配置都会以新增方式保存；即使 ID 相同，也不会覆盖本机已有配置。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _importConfiguration(context),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('导入配置'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportConfiguration(BuildContext context) async {
    final cloudService = context.read<CloudService>();
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final location = await getSaveLocation(
      suggestedName: 'gopic-config-$date.json',
      acceptedTypeGroups: const [ConfigurationScreen._jsonTypeGroup],
    );
    if (!context.mounted) {
      return;
    }
    if (location == null) {
      _showMessage(context, '已取消导出');
      return;
    }

    try {
      final source = await cloudService.exportConfiguration();
      await File(location.path).writeAsString(source);
      if (context.mounted) {
        _showMessage(context, '配置已导出');
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, '导出配置失败');
      }
    }
  }

  Future<void> _importConfiguration(BuildContext context) async {
    final cloudService = context.read<CloudService>();
    final file = await openFile(
      acceptedTypeGroups: const [ConfigurationScreen._jsonTypeGroup],
    );
    if (!context.mounted) {
      return;
    }
    if (file == null) {
      _showMessage(context, '已取消导入');
      return;
    }

    try {
      final source = await file.readAsString();
      final result = await cloudService.importConfiguration(source);
      if (context.mounted) {
        _showMessage(context, '配置已导入：新增 ${result.added} 项');
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, '导入配置失败，请确认文件格式正确');
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setLaunchAtLogin(bool enabled) async {
    final previous = _launchAtLoginEnabled ?? false;
    setState(() => _isUpdatingLaunchAtLogin = true);
    try {
      await _launchAtLoginService.setEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _launchAtLoginEnabled = enabled;
        _isUpdatingLaunchAtLogin = false;
      });
      _showMessage(context, enabled ? '已开启开机自启动' : '已关闭开机自启动');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _launchAtLoginEnabled = previous;
        _isUpdatingLaunchAtLogin = false;
      });
      _showMessage(context, '设置开机自启动失败');
    }
  }

  Future<void> _confirmClearCache(CacheSummary summary) async {
    final historyService = context.read<HistoryService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除本地缓存'),
        content: Text(
          '将清除本机 ${summary.fileCount} 个缓存文件（${formatBytes(summary.totalBytes)}）。上传历史和云端文件不会被删除，确定吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }

    try {
      await historyService.clearCache();
      if (!mounted) {
        return;
      }
      setState(() {
        _cacheSummary = historyService.cacheSummary();
      });
      _showMessage(context, '本地缓存已清除');
    } catch (_) {
      if (mounted) {
        _showMessage(context, '清除本地缓存失败');
      }
    }
  }

  Future<void> _confirmClearHistory() async {
    final historyService = context.read<HistoryService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除上传历史'),
        content: const Text('将清除所有图床上传历史。云端文件和本地缓存不会被删除，确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }

    try {
      await historyService.clear(deleteCache: false);
      if (!mounted) {
        return;
      }
      _showMessage(context, '已清除上传历史');
    } catch (_) {
      if (mounted) {
        _showMessage(context, '清除上传历史失败');
      }
    }
  }
}
