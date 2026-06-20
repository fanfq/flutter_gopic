import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/theme.dart';
import 'models/history_model.dart';
import 'models/cloud_model.dart';
import 'services/history_service.dart';
import 'services/cloud_service.dart';
import 'services/tray_service.dart';
import 'services/upload_service.dart';
import 'screens/upload_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/cloud_screen.dart';
import 'screens/configuration_screen.dart';

const _fallbackAppVersion = '1.0.0';
typedef AppVersionLoader = Future<String> Function();

Future<String> _loadAppVersionFromPackage() async {
  final packageInfo = await PackageInfo.fromPlatform();
  return _formatAppVersion(packageInfo.version, packageInfo.buildNumber);
}

String _formatAppVersion(String version, String buildNumber) {
  final trimmedVersion = version.trim();
  final trimmedBuildNumber = buildNumber.trim();
  if (trimmedBuildNumber.isEmpty) {
    return trimmedVersion.isEmpty ? _fallbackAppVersion : trimmedVersion;
  }
  final displayVersion = trimmedVersion.isEmpty
      ? _fallbackAppVersion
      : trimmedVersion;
  return '$displayVersion ($trimmedBuildNumber)';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GoPicApp());
}

class GoPicApp extends StatelessWidget {
  const GoPicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<CloudService>(create: (_) => CloudService()),
        Provider<HistoryService>(create: (_) => HistoryService()),
        ProxyProvider2<CloudService, HistoryService, UploadService>(
          create: (context) => UploadService(
            cloudService: context.read<CloudService>(),
            historyService: context.read<HistoryService>(),
          ),
          update: (context, cloud, history, previous) =>
              previous ??
              UploadService(cloudService: cloud, historyService: history),
        ),
        ProxyProvider<UploadService, TrayService>(
          update: (context, upload, previous) =>
              previous ?? TrayService(uploadService: upload),
        ),
        ChangeNotifierProvider<CloudModel>(
          create: (context) => context.read<CloudService>().model,
        ),
        ChangeNotifierProvider<HistoryModel>(
          create: (context) => context.read<HistoryService>().model,
        ),
      ],
      child: Consumer<TrayService>(
        builder: (context, tray, child) {
          // Start the menu-bar channel once the service is available.
          WidgetsBinding.instance.addPostFrameCallback((_) => tray.start());
          return child!;
        },
        child: MaterialApp(
          title: 'GoPic',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
          home: const HomeScreen(appVersionLoader: _loadAppVersionFromPackage),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final AppVersionLoader appVersionLoader;
  const HomeScreen({super.key, required this.appVersionLoader});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  CloudProvider _cloudProvider = CloudProvider.cloudflareR2;

  var _appVersion = _fallbackAppVersion;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final appVersion = await widget.appVersionLoader();
      if (!mounted) {
        return;
      }
      setState(() => _appVersion = appVersion);
    } catch (_) {
      // Keep the fallback version visible if package metadata is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const UploadScreen(),
      const GalleryScreen(),
      CloudScreen(selectedProvider: _cloudProvider),
      const ConfigurationScreen(),
    ];
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 1040
              ? 1040.0
              : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Row(
                children: [
                  _MacSidebar(
                    selectedIndex: _index,
                    selectedCloudProvider: _cloudProvider,
                    onSelected: (i) => setState(() => _index = i),
                    onCloudProviderSelected: (provider) => setState(() {
                      _index = 2;
                      _cloudProvider = provider;
                    }),
                    appVersion: _appVersion,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: screens[_index]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MacSidebar extends StatelessWidget {
  const _MacSidebar({
    required this.selectedIndex,
    required this.selectedCloudProvider,
    required this.onSelected,
    required this.onCloudProviderSelected,
    required this.appVersion,
  });

  final int selectedIndex;
  final CloudProvider selectedCloudProvider;
  final ValueChanged<int> onSelected;
  final ValueChanged<CloudProvider> onCloudProviderSelected;
  final String appVersion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cloud = context.watch<CloudModel>();
    return Container(
      width: 220,
      color: scheme.surfaceContainer,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 18),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Image.asset("assets/icon.png"),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'GoPic',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              _SidebarItem(
                selected: selectedIndex == 0,
                icon: Icons.cloud_upload_outlined,
                selectedIcon: Icons.cloud_upload_rounded,
                label: '上传',
                onTap: () => onSelected(0),
              ),
              _SidebarItem(
                selected: selectedIndex == 1,
                icon: Icons.photo_library_outlined,
                selectedIcon: Icons.photo_library_rounded,
                label: '图床',
                onTap: () => onSelected(1),
              ),
              _SidebarItem(
                selected: selectedIndex == 2,
                icon: Icons.wb_cloudy_outlined,
                selectedIcon: Icons.wb_cloudy_rounded,
                label: '云服务',
                onTap: () => onSelected(2),
              ),

              if (selectedIndex == 2)
                Padding(
                  padding: const EdgeInsets.only(left: 18, top: 2, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final provider in CloudProvider.values)
                        _SidebarSubItem(
                          selected: provider == selectedCloudProvider,
                          label: cloud.providerMenuLabel(provider),
                          onTap: () => onCloudProviderSelected(provider),
                        ),
                    ],
                  ),
                ),

              _SidebarItem(
                selected: selectedIndex == 3,
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: '配置',
                onTap: () => onSelected(3),
              ),

              const Spacer(),

              // Text(
              //   '拖拽图片到状态栏图标可快速上传',
              //   style: Theme.of(context).textTheme.labelSmall?.copyWith(
              //     color: scheme.onSurfaceVariant,
              //   ),
              // ),
              _SidebarFooter(
                versionLabel: '版本 $appVersion',
                aboutLabel: 'about',
                onAbout: () => launchUrl(
                  Uri.parse('https://github.com/fanfq/flutter_gopic'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSubItem extends StatelessWidget {
  const _SidebarSubItem({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : scheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 19,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.versionLabel,
    required this.aboutLabel,
    required this.onAbout,
  });

  final String versionLabel;
  final String aboutLabel;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0x94FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              versionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                ///color: _MacColors.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: aboutLabel,
            child: CupertinoButton(
              minimumSize: const Size.square(28),
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(7),
              color: const Color(0xFFE4E5EA),
              onPressed: onAbout,
              child: const Icon(
                Icons.info_outline,
                size: 16,
                //color: _MacColors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
