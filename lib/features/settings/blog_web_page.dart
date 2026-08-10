import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';

/// In-app web page with Fructa's own chrome. Embeds a URL (the fructa.africa
/// blog) inside a themed Scaffold + AppBar, so reading a post never leaves the
/// app. Device/back-gesture walks the site's history first, then pops the page.
class BlogWebPage extends StatefulWidget {
  const BlogWebPage({super.key, required this.url, this.title = 'Blog'});

  final String url;
  final String title;

  @override
  State<BlogWebPage> createState() => _BlogWebPageState();
}

class _BlogWebPageState extends State<BlogWebPage> {
  late final WebViewController _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _progress = 0);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 1);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _progress = 1);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Match the webview backdrop to the theme so there's no white flash, and
    // re-apply on light/dark switches.
    _controller.setBackgroundColor(context.c.bg);
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final loading = _progress < 1.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          foregroundColor: c.text,
          scrolledUnderElevation: 0,
          elevation: 0,
          title: Text(
            widget.title,
            style: TextStyle(
              color: c.text,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh, color: c.muted),
              onPressed: () => _controller.reload(),
              tooltip: 'Reload',
            ),
          ],
          bottom: loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    minHeight: 2,
                    backgroundColor: c.s2,
                    color: c.accent,
                  ),
                )
              : null,
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
