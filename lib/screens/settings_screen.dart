import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/musico_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.appState,
    this.showBackButton = false,
    super.key,
  });

  final AppState appState;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1050;
    final playback = _SettingsGroup(
      title: 'Playback and library',
      children: [
        _SettingsSwitch(
          icon: Icons.sort_by_alpha_outlined,
          title: 'Sort music alphabetically',
          detail: 'Keep your saved tracks in title order.',
          value: appState.sortAlphabetically,
          onChanged: appState.setSortAlphabetically,
        ),
        const Divider(height: 1),
        _SettingsSwitch(
          icon: Icons.shuffle_outlined,
          title: 'Shuffle',
          detail: 'Choose a random next track when playback advances.',
          value: appState.shuffle,
          onChanged: (_) => appState.toggleShuffle(),
        ),
        const Divider(height: 1),
        _SettingsSwitch(
          icon: Icons.repeat_one_outlined,
          title: 'Repeat current track',
          detail: 'Play the current song again when it ends.',
          value: appState.repeatOne,
          onChanged: (_) => appState.toggleRepeatOne(),
        ),
        const Divider(height: 1),
        _SettingsSwitch(
          icon: Icons.playlist_play_outlined,
          title: 'Autoplay next track',
          detail: 'Continue to the next song when the current one ends.',
          value: appState.autoplay,
          onChanged: appState.setAutoplay,
        ),
        const Divider(height: 1),
        _SettingsVolume(appState: appState),
      ],
    );
    final reminders = _SettingsGroup(
      title: 'Release reminders',
      children: [
        _SettingsSwitch(
          icon: Icons.notifications_active_outlined,
          title: 'Anime episode and premiere alerts',
          detail: appState.notificationsAvailable
              ? Platform.isAndroid
                    ? 'Android asks for notification access when you turn this on.'
                    : 'Notify about upcoming titles saved to your watchlist.'
              : 'Native notifications are not currently available.',
          value: appState.notificationsEnabled,
          onChanged: appState.notificationsAvailable
              ? (enabled) => _setNotifications(context, enabled)
              : null,
        ),
        if (appState.supportsDesktopBackgroundRefresh) ...[
          const Divider(height: 1),
          _SettingsSwitch(
            icon: Icons.sync_outlined,
            title: 'Refresh schedule while Musico is open',
            detail: 'Check AniList every ten minutes; refresh stops when the app closes.',
            value: appState.backgroundAutoRefresh,
            onChanged: appState.setBackgroundAutoRefresh,
          ),
        ],
        if (appState.errorMessage != null) ...[
          const Divider(height: 1),
          _InlineMessage(
            message: appState.errorMessage!,
            isError: true,
            actionLabel: 'Dismiss',
            onPressed: appState.dismissError,
          ),
        ],
      ],
    );
    final privacy = _SettingsGroup(
      title: 'Privacy',
      children: [
        const _SettingsInfo(
          icon: Icons.language_outlined,
          title: 'Lyrics use your internet connection',
          detail: 'Musico sends a track title and artist to LRCLIB. Audio files stay on this device.',
        ),
        const Divider(height: 1),
        _SettingsInfo(
          icon: Icons.folder_open_outlined,
          title: 'Imports use the system file picker',
          detail: Platform.isAndroid
              ? 'Musico can open only the files you select; broad storage access is not needed.'
              : 'Musico reads only the media files you select.',
        ),
        const Divider(height: 1),
        const _SettingsInfo(
          icon: Icons.verified_outlined,
          title: 'Downloads keep their license details',
          detail: 'Commons downloads are license-checked and retain their attribution.',
        ),
      ],
    );
    final backup = _BackupSettings(appState: appState);
    final settingsContent = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [playback, const SizedBox(height: 28), privacy],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  children: [reminders, const SizedBox(height: 28), backup],
                ),
              ),
            ],
          )
        : Column(
            children: [
              playback,
              const SizedBox(height: 25),
              reminders,
              const SizedBox(height: 25),
              privacy,
              const SizedBox(height: 25),
              backup,
            ],
          );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        wide
            ? 52
            : showBackButton
            ? 12
            : 26,
        showBackButton ? 12 : 33,
        wide ? 52 : 26,
        38,
      ),
      children: [
        Row(
          children: [
            if (showBackButton) ...[
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                'Settings',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: MediaQuery.sizeOf(context).width > 600 ? 43 : 36,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Make Musico work the way you do.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: MusicoPalette.muted),
        ),
        const SizedBox(height: 25),
        settingsContent,
        if (appState.settingsErrorMessage != null) ...[
          const SizedBox(height: 12),
          _InlineMessage(
            message: appState.settingsErrorMessage!,
            isError: true,
            actionLabel: 'Dismiss',
            onPressed: appState.dismissSettingsError,
          ),
        ],
      ],
    );
  }

  Future<void> _setNotifications(BuildContext context, bool enabled) async {
    if (enabled) {
      await appState.requestAiringNotifications();
    } else {
      await appState.disableAiringNotifications();
    }
    if (!context.mounted) return;
    if (appState.errorMessage case final message?) {
      showMusicoToast(context, message: message, isError: true);
    } else {
      showMusicoToast(
        context,
        message: enabled
            ? 'Release reminders are on.'
            : 'Release reminders are off.',
      );
    }
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Column(children: children),
      ],
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.icon,
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 8, 11, 8),
      child: Row(
        children: [
          _SettingsIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingsInfo extends StatelessWidget {
  const _SettingsInfo({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      child: Row(
        children: [
          _SettingsIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: MusicoPalette.sky,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 17, color: MusicoPalette.forestLight),
    );
  }
}

class _SettingsVolume extends StatelessWidget {
  const _SettingsVolume({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 10),
      child: Row(
        children: [
          const _SettingsIcon(icon: Icons.volume_up_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Player volume',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Slider(value: appState.volume, onChanged: appState.setVolume),
              ],
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${(appState.volume * 100).round()}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupSettings extends StatelessWidget {
  const _BackupSettings({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final busy = appState.isCreatingBackup || appState.isRestoringBackup;
    return _SettingsGroup(
      title: 'Backup and restore',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A backup includes your settings, saved anime, Spotify playlist metadata, downloaded music, imported audio, and local videos.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => _runBackup(context, create: true),
                    icon: appState.isCreatingBackup
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MusicoPalette.white,
                            ),
                          )
                        : const Icon(Icons.archive_outlined, size: 17),
                    label: Text(
                      appState.isCreatingBackup
                          ? 'Creating backup…'
                          : 'Create backup',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _confirmRestore(context),
                    icon: appState.isRestoringBackup
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.settings_backup_restore_outlined,
                            size: 17,
                          ),
                    label: Text(
                      appState.isRestoringBackup
                          ? 'Restoring…'
                          : 'Restore backup',
                    ),
                  ),
                ],
              ),
              if (appState.backupMessage case final message?) ...[
                const SizedBox(height: 10),
                _InlineMessage(message: message, isError: false),
              ],
              if (appState.backupErrorMessage case final error?) ...[
                const SizedBox(height: 10),
                _InlineMessage(message: error, isError: true),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace this Musico library?'),
        content: const Text(
          'Restoring replaces your saved music and videos, watchlist, and settings with the contents of the selected backup. Existing media files are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose backup'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _runBackup(context, create: false);
    }
  }

  Future<void> _runBackup(BuildContext context, {required bool create}) async {
    if (create) {
      await appState.createBackup();
    } else {
      await appState.restoreBackup();
    }
    if (!context.mounted) return;
    if (appState.backupErrorMessage case final error?) {
      showMusicoToast(context, message: error, isError: true);
    } else if (appState.backupMessage case final message?) {
      showMusicoToast(context, message: message);
    }
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.message,
    required this.isError,
    this.actionLabel,
    this.onPressed,
  });

  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: isError ? MusicoPalette.error : MusicoPalette.moss,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isError ? MusicoPalette.error : MusicoPalette.moss,
              ),
            ),
          ),
          if (actionLabel != null && onPressed != null)
            TextButton(onPressed: onPressed, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
