import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

class EmbedPlayerPage extends StatefulWidget {
  const EmbedPlayerPage({
    required this.title,
    required this.embedUrl,
    this.subtitle,
    this.onFallback,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String embedUrl;
  final VoidCallback? onFallback;

  @override
  State<EmbedPlayerPage> createState() => _EmbedPlayerPageState();
}

class _EmbedPlayerPageState extends State<EmbedPlayerPage> {
  late final WebViewController _controller;
  bool _fellBack = false;
  bool? _lastLandscape;

  void _syncSystemUi(bool isLandscape) {
    if (_lastLandscape == isLandscape) return;
    _lastLandscape = isLandscape;
    if (isLandscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _triggerFallback() {
    if (_fellBack || widget.onFallback == null || !mounted) return;
    _fellBack = true;
    Navigator.of(context).pop();
    widget.onFallback!();
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'MusicoBridge',
        onMessageReceived: (message) {
          if (message.message == 'close' && mounted) {
            Navigator.of(context).pop();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onHttpError: (error) {
            if (error.request?.uri.toString() == widget.embedUrl &&
                (error.response?.statusCode ?? 0) >= 400) {
              _triggerFallback();
            }
          },
          onPageFinished: (_) async {
            try {
              final title = await _controller.getTitle();
              if (title != null && title.contains('404')) {
                _triggerFallback();
                return;
              }
              await _controller.runJavaScript('''
                (function() {
                  if (!window.__escListenerAdded) {
                    window.__escListenerAdded = true;
                    document.addEventListener('keydown', function(e) {
                      if (e.key === 'Escape' && window.MusicoBridge) {
                        window.MusicoBridge.postMessage('close');
                      }
                    });
                    var style = document.createElement('style');
                    style.textContent = 'button, a, [role="button"] { min-width: 44px !important; min-height: 44px !important; cursor: pointer !important; }';
                    document.head && document.head.appendChild(style);
                  }
                  if (window.__rangersSelected) return;
                  window.__rangersSelected = true;
                  function selectRangers() {
                    var btns = Array.from(document.querySelectorAll('button, a, div, span, li'));
                    var rangers = btns.find(function(el) {
                      return el.textContent && el.textContent.trim().toLowerCase() === 'rangers';
                    });
                    if (rangers) { rangers.click(); return true; }
                    var choose = btns.find(function(el) {
                      return el.textContent && el.textContent.trim().toLowerCase().includes('choose server');
                    });
                    if (choose) {
                      choose.click();
                      setTimeout(function() {
                        var items = Array.from(document.querySelectorAll('button, a, div, span, li'));
                        var r = items.find(function(el) {
                          return el.textContent && el.textContent.trim().toLowerCase() === 'rangers';
                        });
                        if (r) r.click();
                      }, 300);
                      return true;
                    }
                    return false;
                  }
                  if (!selectRangers()) {
                    setTimeout(selectRangers, 800);
                  }
                })();
              ''');
            } on Object {
              // Ignore title/JS check errors.
            }
          },
          onNavigationRequest: (request) {
            if (!request.isMainFrame) {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            final host = uri?.host.toLowerCase() ?? '';
            if (host.endsWith('vidlink.pro') ||
                host.endsWith('vidcore.org') ||
                host.endsWith('vidsrc.icu') ||
                host.endsWith('vidsrc.to') ||
                host.endsWith('peachify.net') ||
                host.endsWith('moonflix.website')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.embedUrl));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    _syncSystemUi(isLandscape);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: Colors.black,
      appBar: isLandscape
          ? null
          : AppBar(
              toolbarHeight: 60,
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              leadingWidth: 56,
              leading: IconButton(
                iconSize: 26,
                padding: const EdgeInsets.all(14),
                constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),
      body: SafeArea(
        top: !isLandscape,
        bottom: !isLandscape,
        child: WebViewWidget(controller: _controller),
      ),
    ),
    ),
    );
  }
}
