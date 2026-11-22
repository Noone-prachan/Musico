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

import 'screens/anime_screen.dart';
import 'screens/music_catalog_sheet.dart';
import 'screens/music_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/watchlist_screen.dart';
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
    // Video playback is optional; the music library must still start.
    debugPrint('Media playback could not be initialized: $error\n$stackTrace');
  }
  if (Platform.isAndroid) {
    // androidNotificationOngoing and androidStopForegroundOnPause must not
    // both conflict: ongoing=true requires stopForegroundOnPause=false,
    // but audio_service asserts they are consistent — keep ongoing=false so
    // the notification is dismissible and the assertion is satisfied.
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
      // Saved preferences must never keep the window from opening.
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
      theme: MusicoTheme.dark,
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
                            fontFamily: 'Space Grotesk',
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
      theme: MusicoTheme.dark,
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
                          fontFamily: 'Space Grotesk',
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
    theme: MusicoTheme.dark,
    home: const AuroraBackground(child: _MusicoHome()),
  );
}

class _MusicoHome extends StatefulWidget {
  const _MusicoHome();

  @override
  State<_MusicoHome> createState() => _MusicoHomeState();
}

class _MusicoHomeState extends State<_MusicoHome> {
  late final AppState _appState;
  int _selectedPage = 0;
  String? _startupError;

  static const _pageTitles = [
    'Music',
    'Anime calendar',
    'Watchlist',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _appState = AppState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _appState.initialize();
    } on Object catch (error, stackTrace) {
      debugPrint('Musico could not finish starting: $error\n$stackTrace');
      // Only surface a banner for truly unrecoverable errors, not network/
      // playlist-fetch failures that _appState already handles internally.
      if (mounted && !_appState.setupCompleted) {
        // Setup is blocked — show a helpful message instead of a generic one.
        // The setup dialog below will still appear; don't double-banner.
      } else if (mounted) {
        setState(() {
          _startupError =
              'Musico could not finish loading. Restart the app and try again.';
        });
      }
    }
    if (!mounted) return;
    // Always clear the startup-error banner once setup is confirmed complete.
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

                          // Determine the best writable candidate.
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

                          // Update in-memory state immediately so the app
                          // works even if the prefs write is slow/fails.
                          _appState.mediaStorageRoot = chosenRoot;
                          _appState.setupCompleted = true;

                          // Fire-and-forget the prefs write; never block UI on it.
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
    if (index < 0 || index >= _pageTitles.length) return;
    setState(() => _selectedPage = index);
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
                              title: _pageTitles[_selectedPage],
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
                        title: _pageTitles[_selectedPage],
                        isWifiConnected: _appState.isWifiConnected,
                        hasNetworkConnection: _appState.hasNetworkConnection,
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
                        NavigationBar(
                          selectedIndex: _selectedPage,
                          onDestinationSelected: _selectPage,
                          height: 62,
                          labelBehavior:
                              NavigationDestinationLabelBehavior.alwaysShow,
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.library_music_outlined),
                              selectedIcon: Icon(Icons.library_music_rounded),
                              label: 'Music',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.calendar_month_outlined),
                              selectedIcon: Icon(Icons.calendar_month_rounded),
                              label: 'Anime',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.bookmarks_outlined),
                              selectedIcon: Icon(Icons.bookmarks_rounded),
                              label: 'Saved',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.settings_outlined),
                              selectedIcon: Icon(Icons.settings_rounded),
                              label: 'Settings',
                            ),
                          ],
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
      0 => MusicScreen(
        appState: _appState,
        onOpenCatalog: () => showMusicCatalog(context, _appState),
      ),
      1 => AnimeScreen(appState: _appState),
      2 => WatchlistScreen(appState: _appState),
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
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -.75,
        backgroundColor: MusicoPalette.paper,
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: Text('Music'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: Text('Anime'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks_rounded),
            label: Text('Saved'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
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
                          color: MusicoPalette.white,
                          fontFamily: 'Space Grotesk',
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
            selectedIcon: Icons.library_music_rounded,
            label: 'Music',
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          _NavigationItem(
            icon: Icons.calendar_month_outlined,
            selectedIcon: Icons.calendar_month_rounded,
            label: 'Anime calendar',
            selected: selectedIndex == 1,
            onTap: () => onSelected(1),
          ),
          _NavigationItem(
            icon: Icons.bookmarks_outlined,
            selectedIcon: Icons.bookmarks_rounded,
            label: 'Watchlist',
            selected: selectedIndex == 2,
            onTap: () => onSelected(2),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Divider(color: MusicoPalette.glass, height: 1),
          ),
          _NavigationItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: 'Settings',
            selected: selectedIndex == 3,
            onTap: () => onSelected(3),
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
        color: MusicoPalette.white.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(13),
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
                          fontFamily: 'IBM Plex Mono',
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .6,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        metadata.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MusicoPalette.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        metadata.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MusicoPalette.softInk,
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
    color: MusicoPalette.white.withValues(alpha: .16),
    child: const Icon(
      Icons.graphic_eq_rounded,
      color: MusicoPalette.olive,
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
                          ? MusicoPalette.forest
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
    required this.title,
    required this.isWifiConnected,
    required this.hasNetworkConnection,
    this.desktop = false,
  });

  final String title;
  final bool isWifiConnected;
  final bool hasNetworkConnection;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 29 : 19),
      decoration: const BoxDecoration(
        color: MusicoPalette.canvas,
        border: Border(bottom: BorderSide(color: MusicoPalette.line)),
      ),
      child: Row(
        children: [
          if (!desktop) ...[
            const MusicoLogo(size: 31),
            const SizedBox(width: 9),
          ],
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
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
                      ? MusicoPalette.forest
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
