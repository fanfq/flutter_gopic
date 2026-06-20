import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/mac_ui.dart';
import '../models/cloud_model.dart';
import '../services/cloud_service.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key, required this.selectedProvider});

  final CloudProvider selectedProvider;

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  String? _selectedProfileId;

  final _name = TextEditingController();
  final _accountId = TextEditingController();
  final _accessKey = TextEditingController();
  final _secretKey = TextEditingController();
  final _bucket = TextEditingController();
  final _endpoint = TextEditingController();
  final _domain = TextEditingController();
  final _pathPrefix = TextEditingController();
  final _region = TextEditingController();

  bool _enabled = false;
  bool _usePathStyle = true;
  bool _obscureSecret = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final model = context.read<CloudModel>();
    final active = model.activeProfile;
    final profiles = model.profilesFor(widget.selectedProvider);
    _selectedProfileId = active?.provider == widget.selectedProvider
        ? active?.id
        : (profiles.isEmpty ? null : profiles.first.id);
    _loadSelectedProfile(model);
    _initialized = true;
  }

  @override
  void didUpdateWidget(covariant CloudScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProvider == widget.selectedProvider) return;
    final model = context.read<CloudModel>();
    final profiles = model.profilesFor(widget.selectedProvider);
    setState(() {
      _selectedProfileId = profiles.isEmpty ? null : profiles.first.id;
      _loadSelectedProfile(model);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _accountId.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _bucket.dispose();
    _endpoint.dispose();
    _domain.dispose();
    _pathPrefix.dispose();
    _region.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<CloudModel>();
    final profiles = model.profilesFor(widget.selectedProvider);
    final selected = _selectedProfile(model);

    return MacPage(
      title: '云服务 · ${widget.selectedProvider.label}',
      subtitle: '管理 ${widget.selectedProvider.label} 的多套参数，启用后可在上传和图床页面作为默认服务',
      actions: [
        FilledButton.icon(
          onPressed: selected == null ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
      ],
      maxWidth: 1120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 230, child: _profileList(model, profiles)),
          const SizedBox(width: 14),
          Expanded(
            child: selected == null
                ? const SizedBox.shrink()
                : _profileEditor(selected),
          ),
        ],
      ),
    );
  }

  Widget _profileList(CloudModel model, List<CloudProfile> profiles) {
    return MacPanel(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '配置项',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '新增配置',
                icon: const Icon(Icons.add_rounded),
                onPressed: () {
                  model.addProfile(widget.selectedProvider);
                  context.read<CloudService>().save();
                  setState(() {
                    _selectedProfileId = model
                        .profilesFor(widget.selectedProvider)
                        .last
                        .id;
                    _loadSelectedProfile(model);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final profile in profiles)
            _ProfileButton(
              selected: profile.id == _selectedProfileId,
              profile: profile,
              onTap: () {
                setState(() {
                  _selectedProfileId = profile.id;
                  _loadProfile(profile);
                });
              },
              onDelete: () => _deleteProfile(profile),
            ),
        ],
      ),
    );
  }

  Widget _profileEditor(CloudProfile profile) {
    final unsupported = !profile.isUploadSupported;
    final isQiniu = profile.provider == CloudProvider.qiniu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MacPanel(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${profile.provider.label} 参数',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text('启用', style: Theme.of(context).textTheme.bodySmall),
                  Switch(
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (unsupported) ...[
                const SizedBox(height: 8),
                _infoBanner(
                  '${profile.provider.label} 当前仅支持保存参数和默认选择，上传协议待接入。',
                ),
              ],
              const SizedBox(height: 12),
              _field(_name, '配置名称', hint: '${profile.provider.label} 默认'),
              if (!isQiniu)
                _field(
                  _accountId,
                  'Account / App ID',
                  hint: '可选，用于记录账号或 App ID',
                ),
              _field(
                _accessKey,
                isQiniu ? 'AccessKey' : 'Access Key ID',
                hint: '访问密钥 ID',
              ),
              _passwordField(),
              _field(_bucket, 'Bucket 名称', hint: '例如 my-images'),
              _field(
                _endpoint,
                isQiniu ? '上传域名' : 'Endpoint',
                hint: isQiniu
                    ? 'https://up-z0.qiniup.com'
                    : 'https://example.endpoint.com',
              ),
              if (!isQiniu)
                _field(
                  _region,
                  'Region',
                  hint: profile.provider == CloudProvider.cloudflareR2
                      ? 'auto'
                      : 'us-east-1',
                ),
              _field(_domain, '公网 URL 前缀', hint: 'https://cdn.example.com'),
              _field(_pathPrefix, '路径前缀', hint: '例如 images/'),
              if (!isQiniu)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _usePathStyle,
                  title: const Text('Path-style URL'),
                  subtitle: const Text('多数 S3 兼容服务可保持启用'),
                  onChanged: (value) => setState(() => _usePathStyle = value),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _helpCard(profile.provider),
      ],
    );
  }

  Widget _infoBanner(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(hintText: hint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              'Secret Access Key',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _secretKey,
              obscureText: _obscureSecret,
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: _obscureSecret ? '显示' : '隐藏',
                  icon: Icon(
                    _obscureSecret ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscureSecret = !_obscureSecret),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpCard(CloudProvider provider) {
    return MacPanel(
      child: Text(switch (provider) {
        CloudProvider.cloudflareR2 =>
          'R2：Endpoint 通常为 https://<accountId>.r2.cloudflarestorage.com，Region 使用 auto。',
        CloudProvider.awsS3 =>
          'S3：Endpoint 可填写 https://s3.<region>.amazonaws.com，Region 填写桶所在区域。',
        CloudProvider.tencentCos =>
          '腾讯云 COS：可使用 S3 兼容 Endpoint，例如 https://cos.<region>.myqcloud.com。',
        CloudProvider.aliyunOss =>
          '阿里云 OSS：可使用 S3 兼容 Endpoint，Region 按桶所在区域填写。',
        CloudProvider.qiniu =>
          '七牛云：填写 AccessKey、SecretKey、Bucket、上传域名和公网 URL 前缀。上传域名按空间区域选择，例如华东 z0 使用 https://up-z0.qiniup.com。',
      }, style: const TextStyle(height: 1.5)),
    );
  }

  CloudProfile? _selectedProfile(CloudModel model) {
    final profiles = model.profilesFor(widget.selectedProvider);
    if (profiles.isEmpty) return null;
    return profiles.firstWhere(
      (p) => p.id == _selectedProfileId,
      orElse: () => profiles.first,
    );
  }

  void _loadSelectedProfile(CloudModel model) {
    final profile = _selectedProfile(model);
    if (profile != null) _loadProfile(profile);
  }

  void _loadProfile(CloudProfile profile) {
    _name.text = profile.name;
    _accountId.text = profile.accountId;
    _accessKey.text = profile.accessKeyId;
    _secretKey.text = profile.secretAccessKey;
    _bucket.text = profile.bucket;
    _endpoint.text = profile.endpoint;
    _domain.text = profile.publicDomain;
    _pathPrefix.text = profile.pathPrefix;
    _region.text = profile.region;
    _enabled = profile.isEnabled;
    _usePathStyle = profile.usePathStyle;
  }

  Future<void> _save() async {
    final model = context.read<CloudModel>();
    final profile = _selectedProfile(model);
    if (profile == null) return;
    final updated = profile.copyWith(
      name: _name.text.trim().isEmpty
          ? profile.provider.label
          : _name.text.trim(),
      isEnabled: _enabled,
      accountId: _accountId.text.trim(),
      accessKeyId: _accessKey.text.trim(),
      secretAccessKey: _secretKey.text.trim(),
      bucket: _bucket.text.trim(),
      endpoint: _endpoint.text.trim(),
      publicDomain: _domain.text.trim(),
      pathPrefix: _pathPrefix.text.trim(),
      region: _region.text.trim().isEmpty
          ? (profile.provider == CloudProvider.cloudflareR2
                ? 'auto'
                : 'us-east-1')
          : _region.text.trim(),
      usePathStyle: _usePathStyle,
    );
    model.upsertProfile(updated);
    await context.read<CloudService>().save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(updated.isConfigured ? '配置已保存并可用于上传' : '配置已保存，但尚不可用于上传'),
      ),
    );
  }

  Future<void> _deleteProfile(CloudProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配置项'),
        content: Text('确定删除「${profile.name}」吗？此操作不会删除云端文件。'),
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
    if (ok != true || !mounted) return;
    final model = context.read<CloudModel>();
    model.deleteProfile(profile.id);
    await context.read<CloudService>().save();
    final remaining = model.profilesFor(widget.selectedProvider);
    setState(() {
      _selectedProfileId = remaining.isEmpty ? null : remaining.first.id;
      _loadSelectedProfile(model);
    });
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.selected,
    required this.profile,
    required this.onTap,
    required this.onDelete,
  });

  final bool selected;
  final CloudProfile profile;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  profile.isEnabled
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: profile.isEnabled ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        profile.isEnabled
                            ? (profile.isConfigured ? '已启用' : '已启用，参数未完成')
                            : '未启用',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除配置项',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18,color: Colors.redAccent,),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
