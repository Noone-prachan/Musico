import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/local_video_screen.dart';
import 'screens/music_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/streaming_screen.dart';
import 'screens/watchlist_screen.dart';
import 'models/video_track.dart';
import 'models/music_track.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/musico_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } on Object catch (error, stackTrace) {
    debugPrint('Media playback could not be initialized: $error\n$stackTrace');
  }
  if (Platform.isAndroid) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.sideb.side_b.audio',
      androidNotificationChannelName: 'Musico playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
      preloadArtwork: true,
    );
  }
  if (Platform.isWindows) {
    try {
      final preferences = await SharedPreferences.getInstance();
      final installConfig = File(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}musico_setup.json',
      );
      if (await installConfig.exists()) {
        try {
          final decoded = jsonDecode(
            await installConfig.readAsString(),
          ) as Map<String, dynamic>;
          final mediaRoot = decoded['mediaRoot'];
          if (mediaRoot is String && mediaRoot.trim().isNotEmpty) {
            await preferences.setString(
              'sideb.native.media-storage-root.v1',
              mediaRoot.trim(),
            );
            await preferences.setBool('sideb.native.setup-completed.v1', true);
          }
        } on Object catch (error) {
          debugPrint('Musico installer setup could not be read: $error');
        }
      }
      final setupCompleted =
          preferences.getBool('sideb.native.setup-completed.v1') ?? false;
      final mediaRoot = preferences.getString(
        'sideb.native.media-storage-root.v1',
      );
      if (setupCompleted && mediaRoot != null && mediaRoot.isNotEmpty) {
        runApp(const MusicoApp());
      } else {
        runApp(const _WindowsSetupApp());
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Musico could not read saved preferences: $error\n$stackTrace',
      );
      runApp(const MusicoApp());
    }
  } else if (Platform.isAndroid) {
    final preferences = await SharedPreferences.getInstance();
    final permissionPrompted =
        preferences.getBool('sideb.native.permission-prompted.v1') ?? false;
    if (permissionPrompted) {
      runApp(const MusicoApp());
    } else {
      runApp(const _AndroidSetupApp());
    }
  } else {
    runApp(const MusicoApp());
  }
}

class _AndroidSetupApp extends StatefulWidget {
  const _AndroidSetupApp();

  @override
  State<_AndroidSetupApp> createState() => _AndroidSetupAppState();
}

class _AndroidSetupAppState extends State<_AndroidSetupApp> {
  bool _requesting = false;
  String? _status;

  Future<void> _allowPermissions() async {
    setState(() {
      _requesting = true;
      _status = 'Requesting notification access…';
    });
    const channel = MethodChannel('musico/android_setup');
    bool granted = false;
    try {
      granted = await channel.invokeMethod<bool>('requestPermissions') ?? false;
    } on Object catch (error) {
      debugPrint('Android setup permissions could not be requested: $error');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('sideb.native.setup-completed.v1', true);
    await preferences.setBool('sideb.native.permission-prompted.v1', true);
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _status = granted ? 'Notifications enabled.' : 'Notifications are off. You can enable them later in Android settings.';
    });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted) runApp(const MusicoApp());
  }

  Future<void> _continueWithoutPermissions() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('sideb.native.setup-completed.v1', true);
    await preferences.setBool('sideb.native.permission-prompted.v1', true);
    if (mounted) runApp(const MusicoApp());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MusicoTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MusicoLogo(size: 54),
                        const SizedBox(height: 18),
                        const Text(
                          'Enable notifications',
                          style: TextStyle(
                            color: MusicoPalette.ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Notifications support playback controls and reminders. Downloads stay in Musico's private storage, and imports use Android's file picker; broad storage access is not needed.",
                          style: TextStyle(
                            color: MusicoPalette.muted,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        if (_status != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _status!,
                            style: const TextStyle(
                              color: MusicoPalette.softInk,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _requesting
                                  ? null
                                  : _continueWithoutPermissions,
                              child: const Text('Not now'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _requesting ? null : _allowPermissions,
                              child: _requesting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Enable notifications'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowsSetupApp extends StatefulWidget {
  const _WindowsSetupApp();

  @override
  State<_WindowsSetupApp> createState() => _WindowsSetupAppState();
}

class _WindowsSetupAppState extends State<_WindowsSetupApp> {
  String? _recommended;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _recommended = null;
    unawaited(_loadRecommended());
  }

  Future<void> _loadRecommended() async {
    if (!mounted) return;
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!mounted) return;
        setState(() {
          _recommended = '${downloads.path}${Platform.pathSeparator}Musico';
        });
        return;
      }
    } on Object catch (error) {
      debugPrint('Could not resolve the Windows Downloads folder: $error');
    }
    final profile = Platform.environment['USERPROFILE'];
    if (!mounted) return;
    setState(() {
      _recommended = profile == null || profile.isEmpty
          ? '${Directory.systemTemp.path}${Platform.pathSeparator}Musico'
          : '$profile${Platform.pathSeparator}Downloads'
                '${Platform.pathSeparator}Musico';
    });
  }

  Future<bool> _saveRoot(String root) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await _trySaveRoot(root);
    if (!saved) {
      if (mounted) {
        setState(() {
          _error =
              'Access denied: "$root" is not writable. Choose another folder.';
          _saving = false;
        });
      }
      return false;
    } else {
      if (mounted) setState(() => _saving = false);
      return true;
    }
  }

  Future<bool> _trySaveRoot(String root) async {
    Directory? probeDirectory;
    try {
      final directory = Directory(root);
      await directory.create(recursive: true);
      probeDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '.musico-write-test-${DateTime.now().microsecondsSinceEpoch}',
      );
      await probeDirectory.create();
      final probe = File(
        '${probeDirectory.path}${Platform.pathSeparator}write-test',
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      await probeDirectory.delete();
      probeDirectory = null;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('sideb.native.media-storage-root.v1', root);
      await preferences.setBool('sideb.native.setup-completed.v1', true);
      return true;
    } on Object catch (error) {
      debugPrint('Musico storage location was rejected "$root": $error');
      if (probeDirectory != null) {
        try {
          if (await probeDirectory.exists()) {
            await probeDirectory.delete(recursive: true);
          }
        } on Object catch (cleanupError) {
          debugPrint(
            'Musico storage probe could not be cleaned up at '
            '${probeDirectory.path}: $cleanupError',
          );
        }
      }
      return false;
    }
  }

  Future<void> _useRecommended() async {
    final recommended = _recommended;
    if (recommended == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final profile = Platform.environment['USERPROFILE'];
    final candidates = <String>[
      recommended,
      '${Directory.systemTemp.path}${Platform.pathSeparator}Musico',
      if (profile != null && profile.isNotEmpty) ...[
        '$profile${Platform.pathSeparator}Downloads'
            '${Platform.pathSeparator}Musico',
        '$profile${Platform.pathSeparator}Documents'
            '${Platform.pathSeparator}Musico',
        '$profile${Platform.pathSeparator}Desktop'
            '${Platform.pathSeparator}Musico',
        '$profile${Platform.pathSeparator}Musico',
      ],
    ];
    String? savedRoot;
    for (final candidate in candidates.toSet()) {
      if (await _trySaveRoot(candidate)) {
        savedRoot = candidate;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (savedRoot == null) {
      setState(() {
        _error =
            'Musico could not create folders in the recommended locations. '
            'Choose a different storage folder with Browse...';
      });
      return;
    }
    runApp(const MusicoApp());
  }

  Future<void> _chooseFolder() async {
    final selected = await FilePicker.pickDirectory(
      dialogTitle: 'Choose Musico storage folder',
    );
    if (selected == null || !mounted) return;
    final path = selected.toFilePath();
    if (await _saveRoot(path)) {
      runApp(const MusicoApp());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MusicoTheme.light,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MusicoLogo(size: 54),
                      const SizedBox(height: 18),
                      Text(
                        'Where should Musico store your files?',
                        style: const TextStyle(
                          color: MusicoPalette.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'This folder will hold your imported music, videos, artwork, and YouTube downloads.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: MusicoPalette.muted, height: 1.5),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Recommended folder',
                        style: const TextStyle(
                          color: MusicoPalette.softInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: MusicoPalette.canvasAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: MusicoPalette.line),
                        ),
                        child: Text(
                          _recommended ?? 'Finding a writable folder…',
                          style: const TextStyle(
                            color: MusicoPalette.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: MusicoPalette.error),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _saving ? null : _chooseFolder,
                            child: const Text('Choose another folder'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _saving || _recommended == null
                                ? null
                                : _useRecommended,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Use recommended'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MusicoApp extends StatelessWidget {
  const MusicoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Musico',
    debugShowCheckedModeBanner: false,
    theme: MusicoTheme.light,
    home: const AuroraBackground(child: _MusicoHome()),
  );
}

class _MusicoHome extends StatefulWidget {
  const _MusicoHome();

  @override
  State<_MusicoHome> createState() => _MusicoHomeState();
}

class _MusicoHomeState extends State<_MusicoHome> {
  static const _pageCount = 9;

  late final AppState _appState;
  int _selectedPage = 0;
  String? _startupError;

  String? _watchSeed;
  int _watchSeedTick = 0;

  void _openTvWithQuery(String query) {
    setState(() {
      _watchSeed = query;
      _watchSeedTick++;
      _selectedPage = 2;
    });
  }

  @override
  void initState() {
    super.initState();
    _appState = AppState();
    final startPage = int.tryParse(
      Platform.environment['MUSICO_START_PAGE'] ?? '',
    );
    if (startPage != null && startPage >= 0 && startPage < _pageCount) {
      _selectedPage = startPage;
    }
    unawaited(_initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.sizeOf(context).width < 680 && _selectedPage >= 8) {
      _selectedPage = 0;
    }
  }

  Future<void> _initialize() async {
    try {
      await _appState.initialize();
    } on Object catch (error, stackTrace) {
      debugPrint('Musico could not finish starting: $error\n$stackTrace');
      if (mounted && !_appState.setupCompleted) {
      } else if (mounted) {
        setState(() {
          _startupError =
              'Musico could not finish loading. Restart the app and try again.';
        });
      }
    }
    if (!mounted) return;
    if (_appState.setupCompleted && _startupError != null) {
      setState(() => _startupError = null);
    }
    if (!_appState.setupCompleted) {
      await _showFirstRunSetup();
    }
  }

  Future<void> _showFirstRunSetup() async {
    if (Platform.isWindows) {
      final recommended = await _appState.recommendedMediaStorageRoot();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var saving = false;
          String? dialogError;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Choose where Musico stores downloads'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This folder will hold imported music, videos, artwork, and YouTube downloads.',
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Recommended',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      recommended,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        dialogError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final selectedUri = await FilePicker.pickDirectory(
                            dialogTitle: 'Choose Musico storage folder',
                          );
                          if (selectedUri == null || !dialogContext.mounted)
                            return;
                          final selected = selectedUri.toFilePath();
                          setDialogState(() {
                            saving = true;
                            dialogError = null;
                          });
                          try {
                            final ok = await _appState.setMediaStorageRoot(
                              selected,
                            );
                            if (!dialogContext.mounted) return;
                            if (ok) {
                              await _appState.completeSetup();
                              if (mounted) setState(() => _startupError = null);
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } else {
                              setDialogState(() {
                                saving = false;
                                dialogError = _appState.settingsErrorMessage ?? 'That folder could not be used. Try another.';
                              });
                            }
                          } on Object catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                saving = false;
                                dialogError =
                                    'Could not save storage location: $error';
                              });
                            }
                          }
                        },
                  child: const Text('Choose folder'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            saving = true;
                            dialogError = null;
                          });

                          final userProfile =
                              Platform.environment['USERPROFILE'];
                          final candidates = <String>[
                            recommended,
                            if (userProfile != null &&
                                userProfile.isNotEmpty) ...[
                              '$userProfile${Platform.pathSeparator}Downloads'
                                  '${Platform.pathSeparator}Musico',
                              '$userProfile${Platform.pathSeparator}Documents'
                                  '${Platform.pathSeparator}Musico',
                              '$userProfile${Platform.pathSeparator}Musico',
                            ],
                            '${Directory.systemTemp.path}${Platform.pathSeparator}Musico',
                          ];

                          String chosenRoot = recommended;
                          for (final candidate in candidates) {
                            try {
                              final dir = Directory(candidate);
                              await dir.create(recursive: true);
                              final probe = File(
                                '${dir.path}${Platform.pathSeparator}'
                                'musico_write_test',
                              );
                              await probe.writeAsString('ok');
                              await probe.delete();
                              chosenRoot = candidate;
                              break;
                            } on Object {
                              continue;
                            }
                          }

                          _appState.mediaStorageRoot = chosenRoot;
                          _appState.setupCompleted = true;

                          unawaited(
                            SharedPreferences.getInstance()
                                .then((prefs) async {
                                  await prefs.setString(
                                    'sideb.native.media-storage-root.v1',
                                    chosenRoot,
                                  );
                                  await prefs.setBool(
                                    'sideb.native.setup-completed.v1',
                                    true,
                                  );
                                })
                                .catchError((Object _) {}),
                          );

                          if (mounted) setState(() => _startupError = null);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Use recommended'),
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    if (Platform.isAndroid) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Enable Musico permissions'),
          content: const Text(
            'Allow notifications if you want release reminders. Musico stores media in its app-private media folders and does not need broad storage access.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _appState.completeSetup();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () async {
                await _appState.requestAiringNotifications();
                await _appState.completeSetup();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Allow notifications'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    if (index < 0 || index >= _pageCount) return;
    setState(() {
      _selectedPage = index;
      _watchSeed = null;
    });
  }

  void _openCompactSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: MusicoPalette.canvas,
          body: SafeArea(
            child: AnimatedBuilder(
              animation: _appState,
              builder: (context, _) =>
                  SettingsScreen(appState: _appState, showBackButton: true),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appState,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final desktop = width >= 980 && !Platform.isAndroid;
        final rail = width >= 680 && !desktop;
        final showAudioDock =
            _appState.currentVideo == null &&
            (_selectedPage == 0 ||
                _appState.currentTrack != null ||
                _appState.tracks.isNotEmpty);

        return Scaffold(
          body: SafeArea(
            child: desktop
                ? Row(
                    children: [
                      _SideNavigation(
                        appState: _appState,
                        selectedIndex: _selectedPage,
                        onSelected: _selectPage,
                        desktop: true,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            _TopBar(
                              isWifiConnected: _appState.isWifiConnected,
                              hasNetworkConnection:
                                  _appState.hasNetworkConnection,
                              desktop: true,
                            ),
                            if (_startupError != null)
                              _StartupError(message: _startupError!),
                            Expanded(child: _currentScreen()),
                            if (showAudioDock) PlayerDock(appState: _appState),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _TopBar(
                        isWifiConnected: _appState.isWifiConnected,
                        hasNetworkConnection: _appState.hasNetworkConnection,
                        onSettingsPressed: rail ? null : _openCompactSettings,
                      ),
                      if (_startupError != null)
                        _StartupError(message: _startupError!),
                      Expanded(
                        child: Row(
                          children: [
                            if (rail)
                              _SideNavigation(
                                appState: _appState,
                                selectedIndex: _selectedPage,
                                onSelected: _selectPage,
                                desktop: false,
                              ),
                            Expanded(child: _currentScreen()),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          bottomNavigationBar: desktop
              ? null
              : SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showAudioDock)
                        PlayerDock(appState: _appState, compact: true),
                      if (!rail)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: MusicoPalette.canvasAlt,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: MusicoPalette.line),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: NavigationBar(
                                selectedIndex: switch (_selectedPage) {
                                  0 => 0,
                                  1 => 1,
                                  2 => 2,
                                  3 => 3,
                                  _ => 4,
                                },
                                onDestinationSelected: (index) =>
                                    _selectPage(switch (index) {
                                      0 => 0,
                                      1 => 1,
                                      2 => 2,
                                      3 => 3,
                                      _ => 7,
                                    }),
                                height: 62,
                                backgroundColor: Colors.transparent,
                                indicatorColor: MusicoPalette.clayLight,
                                labelBehavior:
                                    NavigationDestinationLabelBehavior
                                        .onlyShowSelected,
                                destinations: const [
                                  NavigationDestination(
                                    icon: Icon(Icons.library_music_outlined),
                                    selectedIcon: Icon(
                                      Icons.library_music_outlined,
                                    ),
                                    label: 'Songs',
                                  ),
                                  NavigationDestination(
                                    icon: Icon(Icons.ondemand_video_outlined),
                                    selectedIcon: Icon(
                                      Icons.ondemand_video_outlined,
                                    ),
                                    label: 'Anime',
                                  ),
                                  NavigationDestination(
                                    icon: Icon(Icons.live_tv_outlined),
                                    selectedIcon: Icon(Icons.live_tv_outlined),
                                    label: 'TV',
                                  ),
                                  NavigationDestination(
                                    icon: Icon(Icons.movie_outlined),
                                    selectedIcon: Icon(Icons.movie_outlined),
                                    label: 'Movies',
                                  ),
                                  NavigationDestination(
                                    icon: Icon(Icons.more_horiz_outlined),
                                    selectedIcon: Icon(
                                      Icons.more_horiz_outlined,
                                    ),
                                    label: 'More',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _currentScreen() {
    final screen = switch (_selectedPage) {
      0 => MusicScreen(appState: _appState),
      1 => StreamingScreen(
        appState: _appState,
        initialTab: 0,
        onOpenTvShows: _openTvWithQuery,
      ),
      2 => StreamingScreen(
        key: ValueKey<String>('tv-$_watchSeedTick'),
        appState: _appState,
        initialTab: 1,
        seedQuery: _watchSeed,
        onOpenTvShows: _openTvWithQuery,
      ),
      3 => StreamingScreen(
        key: ValueKey<String>('movies-$_watchSeedTick'),
        appState: _appState,
        initialTab: 2,
        seedQuery: _watchSeed,
      ),
      4 => MusicPlaylistsScreen(
        appState: _appState,
        onOpenPlaylist: () => _selectPage(0),
      ),
      5 => MusicScreen(appState: _appState, favoritesOnly: true),
      6 => WatchlistScreen(appState: _appState),
      7 => _MoreScreen(appState: _appState, onSelected: _selectPage),
      _ => SettingsScreen(appState: _appState),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(key: ValueKey<int>(_selectedPage), child: screen),
    );
  }
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.appState, required this.onSelected});

  final AppState appState;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final destinations = [
      (label: 'Playlists', icon: Icons.queue_music_outlined, page: 4),
      (label: 'Favorites', icon: Icons.favorite_border_rounded, page: 5),
      (label: 'Watchlist', icon: Icons.bookmarks_outlined, page: 6),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 34),
      children: [
        Text('Your library', style: Theme.of(context).textTheme.displayLarge),
        const SizedBox(height: 5),
        Text(
          'Saved music and titles, all in one place.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: MusicoPalette.muted),
        ),
        const SizedBox(height: 22),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < destinations.length; index++) ...[
                ListTile(
                  leading: Icon(
                    destinations[index].icon,
                    color: MusicoPalette.forest,
                  ),
                  title: Text(destinations[index].label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onSelected(destinations[index].page),
                ),
                if (index < destinations.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            ],
          ),
        ),
        const SizedBox(height: 26),
        Text('On this device', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.live_tv_outlined,
                  color: MusicoPalette.forest,
                ),
                title: const Text('Saved TV episodes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openLocal(context, VideoCategory.tvShow),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: Icon(
                  Icons.movie_outlined,
                  color: MusicoPalette.forest,
                ),
                title: const Text('Saved movies'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openLocal(context, VideoCategory.movie),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openLocal(BuildContext context, VideoCategory category) {
    final label = category == VideoCategory.tvShow
        ? 'Saved TV episodes'
        : 'Saved movies';
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(label)),
          body: LocalVideoScreen(appState: appState, category: category),
        ),
      ),
    );
  }
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.appState,
    required this.selectedIndex,
    required this.onSelected,
    required this.desktop,
  });

  final AppState appState;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    if (!desktop) {
      return NavigationRail(
        selectedIndex: selectedIndex == 8 ? 7 : selectedIndex,
        onDestinationSelected: (index) => onSelected(index == 7 ? 8 : index),
        labelType: NavigationRailLabelType.all,
        groupAlignment: -.75,
        backgroundColor: MusicoPalette.paper,
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_outlined),
            label: Text('Songs'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.ondemand_video_outlined),
            selectedIcon: Icon(Icons.ondemand_video_outlined),
            label: Text('Anime'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv_outlined),
            label: Text('TV shows'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie_outlined),
            label: Text('Movies'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music_outlined),
            label: Text('Playlists'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_border_rounded),
            label: Text('Favorites'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks_outlined),
            label: Text('Watchlist'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_outlined),
            label: Text('Settings'),
          ),
        ],
      );
    }

    return Container(
      width: 224,
      decoration: const BoxDecoration(
        color: MusicoPalette.canvasAlt,
        border: Border(right: BorderSide(color: MusicoPalette.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 16, 30),
            child: Row(
              children: [
                const MusicoLogo(size: 42),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Musico',
                        style: TextStyle(
                          color: MusicoPalette.ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.7,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _NavigationItem(
            icon: Icons.library_music_outlined,
            selectedIcon: Icons.library_music_outlined,
            label: 'Songs',
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          _NavigationItem(
            icon: Icons.ondemand_video_outlined,
            selectedIcon: Icons.ondemand_video_outlined,
            label: 'Anime',
            selected: selectedIndex == 1,
            onTap: () => onSelected(1),
          ),
          _NavigationItem(
            icon: Icons.live_tv_outlined,
            selectedIcon: Icons.live_tv_outlined,
            label: 'TV Shows',
            selected: selectedIndex == 2,
            onTap: () => onSelected(2),
          ),
          _NavigationItem(
            icon: Icons.movie_outlined,
            selectedIcon: Icons.movie_outlined,
            label: 'Movies',
            selected: selectedIndex == 3,
            onTap: () => onSelected(3),
          ),
          _NavigationItem(
            icon: Icons.queue_music_outlined,
            selectedIcon: Icons.queue_music_outlined,
            label: 'Playlists',
            selected: selectedIndex == 4,
            onTap: () => onSelected(4),
          ),
          _NavigationItem(
            icon: Icons.favorite_border_rounded,
            selectedIcon: Icons.favorite_border_rounded,
            label: 'Favorites',
            selected: selectedIndex == 5,
            onTap: () => onSelected(5),
          ),
          _NavigationItem(
            icon: Icons.bookmarks_outlined,
            selectedIcon: Icons.bookmarks_outlined,
            label: 'Watchlist',
            selected: selectedIndex == 6,
            onTap: () => onSelected(6),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Divider(color: MusicoPalette.glass, height: 1),
          ),
          _NavigationItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_outlined,
            label: 'Settings',
            selected: selectedIndex == 8,
            onTap: () => onSelected(8),
          ),
          const Spacer(),
          if (appState.currentTrack case final track?) ...[
            _SidebarNowPlaying(
              track: track,
              playing: appState.isPlaying,
              onTap: () => onSelected(0),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SidebarNowPlaying extends StatelessWidget {
  const _SidebarNowPlaying({
    required this.track,
    required this.playing,
    required this.onTap,
  });

  final MusicTrack track;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final artworkPath = track.artworkPath;
    final metadata = track.displayMetadata;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 3),
      child: Material(
        color: MusicoPalette.paper,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: MusicoPalette.line),
          borderRadius: BorderRadius.circular(13),
        ),
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: artworkPath != null
                      ? Image.file(
                          File(artworkPath),
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const _SidebarArtworkIcon(),
                        )
                      : const _SidebarArtworkIcon(),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playing ? 'NOW PLAYING' : 'PAUSED',
                        style: const TextStyle(
                          color: MusicoPalette.olive,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        metadata.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MusicoPalette.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        metadata.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MusicoPalette.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
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

class _SidebarArtworkIcon extends StatelessWidget {
  const _SidebarArtworkIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    color: MusicoPalette.canvasAlt,
    child: const Icon(
      Icons.graphic_eq_outlined,
      color: MusicoPalette.forestLight,
      size: 18,
    ),
  );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? MusicoPalette.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? MusicoPalette.line : Colors.transparent,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? selectedIcon : icon,
                      color: selected
                          ? MusicoPalette.terracotta
                          : MusicoPalette.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? MusicoPalette.ink
                            : MusicoPalette.muted,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isWifiConnected,
    required this.hasNetworkConnection,
    this.desktop = false,
    this.onSettingsPressed,
  });

  final bool isWifiConnected;
  final bool hasNetworkConnection;
  final bool desktop;
  final VoidCallback? onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: desktop ? 46 : 54,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 29 : 19),
      decoration: const BoxDecoration(
        color: MusicoPalette.canvas,
        border: Border(bottom: BorderSide(color: MusicoPalette.line)),
      ),
      child: Row(
        children: [
          if (!desktop) ...[
            const MusicoLogo(size: 30),
            const SizedBox(width: 9),
            Text(
              'Musico',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
          ],
          const Spacer(),
          Tooltip(
            message: hasNetworkConnection
                ? 'Network connection detected · lyrics lookup is available'
                : 'No network detected · downloaded music remains available',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isWifiConnected
                      ? Icons.wifi_rounded
                      : hasNetworkConnection
                      ? Icons.language_rounded
                      : Icons.wifi_off_rounded,
                  size: 15,
                  color: hasNetworkConnection
                      ? MusicoPalette.forestLight
                      : MusicoPalette.muted,
                ),
                const SizedBox(width: 7),
                Text(
                  isWifiConnected
                      ? 'Wi-Fi'
                      : hasNetworkConnection
                      ? 'Online'
                      : 'Offline',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onSettingsPressed != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Settings',
              onPressed: onSettingsPressed,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(message),
    leading: const Icon(Icons.error_outline_rounded),
    backgroundColor: MusicoPalette.clay,
    actions: [
      TextButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restart Musico to try again.')),
        ),
        child: const Text('Got it'),
      ),
    ],
  );
}
