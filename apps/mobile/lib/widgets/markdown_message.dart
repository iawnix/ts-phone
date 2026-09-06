import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../data/bounded_network_image_loader.dart';
import '../l10n/app_localizations_extensions.dart';
import '../navigation/adaptive_page_route.dart';
import '../theme/ts_phone_theme.dart';
import 'presentation.dart';

class MarkdownMessage extends StatefulWidget {
  const MarkdownMessage({super.key, required this.data});

  final String data;

  @override
  State<MarkdownMessage> createState() => _MarkdownMessageState();
}

class _MarkdownMessageState extends State<MarkdownMessage> {
  bool _previewOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = TsPhoneStatusTheme.resolve(context);
    return MarkdownBody(
      data: widget.data,
      selectable: true,
      softLineBreak: true,
      extensionSet: md.ExtensionSet(
        <md.BlockSyntax>[
          const BlockMathSyntax(),
          ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        ],
        <md.InlineSyntax>[
          InlineMathSyntax(),
          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
        ],
      ),
      builders: <String, MarkdownElementBuilder>{
        'math-inline': MathBuilder(isBlock: false),
        'math-block': MathBuilder(isBlock: true),
        'code': InlineCodeBuilder(),
        'pre': TerminalMarkdownBuilder(),
      },
      imageBuilder: (uri, title, alt) => _buildImage(context, uri, alt),
      onTapLink: (text, href, title) => _openLink(href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
        h1: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h2: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
        h3: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        listBullet: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
        code: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: status.codeForeground,
          backgroundColor: status.codeBackground,
          letterSpacing: 0,
          height: 1.45,
        ),
        codeblockDecoration: BoxDecoration(
          color: status.terminalBackground,
          borderRadius: BorderRadius.circular(TsPhoneRadii.small),
          border: Border.all(
            color: status.terminalMuted.withValues(alpha: 0.34),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(TsPhoneSpacing.medium),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(
            left: BorderSide(color: theme.colorScheme.tertiary, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(
          TsPhoneSpacing.medium,
          TsPhoneSpacing.small,
          TsPhoneSpacing.small,
          TsPhoneSpacing.small,
        ),
        tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant),
        tableHead: TextStyle(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
        ),
        tableBody: theme.textTheme.bodySmall,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: TsPhoneSpacing.small,
          vertical: TsPhoneSpacing.small,
        ),
        a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, Uri uri, String? alt) {
    if (uri.scheme != 'https') {
      return Text(
        alt?.isNotEmpty == true
            ? context.l10n.imageAlt(alt!)
            : context.l10n.blockedNonHttpsImage,
      );
    }
    final description = alt?.trim();
    final source = _imageSource(uri);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _showImagePreview(context, uri, description),
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: TsPhoneSpacing.small,
            vertical: TsPhoneSpacing.xSmall,
          ),
        ),
        icon: const Icon(Icons.image_outlined),
        label: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              description?.isNotEmpty == true
                  ? description!
                  : context.l10n.previewImage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImagePreview(
    BuildContext context,
    Uri uri,
    String? description,
  ) async {
    if (_previewOpen) return;
    _previewOpen = true;
    try {
      await pushTsPhonePage<void>(
        context: context,
        fullscreenDialog: true,
        builder: (_) =>
            _MarkdownImagePreviewPage(uri: uri, description: description),
      );
    } finally {
      _previewOpen = false;
    }
  }

  Future<void> _openLink(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || uri.scheme != 'https') return;
    await _openHttpsUri(uri);
  }
}

String _imageSource(Uri uri) {
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  return uri.hasPort ? '$host:${uri.port}' : host;
}

class _MarkdownImagePreviewPage extends StatefulWidget {
  const _MarkdownImagePreviewPage({
    required this.uri,
    required this.description,
  });

  final Uri uri;
  final String? description;

  @override
  State<_MarkdownImagePreviewPage> createState() =>
      _MarkdownImagePreviewPageState();
}

class _MarkdownImagePreviewPageState extends State<_MarkdownImagePreviewPage> {
  static const _imageLoader = BoundedNetworkImageLoader();

  int _loadAttempt = 0;
  int _loadGeneration = 0;
  BoundedImageDownloadProgress? _progress;
  late Future<BoundedImageData> _image;
  Completer<void>? _abortLoad;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  String get _semanticLabel {
    final description = widget.description;
    return description?.isNotEmpty == true
        ? description!
        : context.l10n.previewImage;
  }

  void _startLoad({bool rebuild = false}) {
    final previousAbort = _abortLoad;
    if (previousAbort != null && !previousAbort.isCompleted) {
      previousAbort.complete();
    }
    final abortLoad = Completer<void>();
    final generation = ++_loadGeneration;
    final future = _imageLoader.load(
      widget.uri,
      abortTrigger: abortLoad.future,
      onProgress: (progress) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() => _progress = progress);
      },
    );
    void updateState() {
      _abortLoad = abortLoad;
      _progress = null;
      _image = future;
      if (rebuild) _loadAttempt += 1;
    }

    if (rebuild) {
      setState(updateState);
    } else {
      updateState();
    }
  }

  Future<void> _retry() async {
    _startLoad(rebuild: true);
  }

  @override
  void dispose() {
    final abortLoad = _abortLoad;
    if (abortLoad != null && !abortLoad.isCompleted) abortLoad.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey<String>('markdown-image-preview-page'),
      backgroundColor: colors.surface,
      appBar: TsGlassAppBar(
        leading: const CloseButton(),
        title: Text(
          _semanticLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('markdown-image-open-browser'),
            onPressed: () => _openHttpsUri(widget.uri),
            tooltip: context.l10n.openInBrowser,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: FutureBuilder<BoundedImageData>(
                key: ValueKey<String>('markdown-preview-image-$_loadAttempt'),
                future: _image,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ImagePreviewFailure(onRetry: _retry);
                  }
                  final image = snapshot.data;
                  if (image == null) {
                    return Center(
                      child: Semantics(
                        label: context.l10n.loadingImage,
                        child: ExcludeSemantics(
                          child: CircularProgressIndicator.adaptive(
                            value: _progress?.fraction,
                          ),
                        ),
                      ),
                    );
                  }
                  return Image.memory(
                    image.bytes,
                    cacheWidth: image.decodeWidth,
                    cacheHeight: image.decodeHeight,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    semanticLabel: _semanticLabel,
                    errorBuilder: (context, error, stackTrace) =>
                        _ImagePreviewFailure(onRetry: _retry),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePreviewFailure extends StatelessWidget {
  const _ImagePreviewFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(TsPhoneSpacing.large),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: TsContentSurface(
            padding: const EdgeInsets.all(TsPhoneSpacing.large),
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: TsPhoneSpacing.medium),
                  Text(
                    context.l10n.imageLoadFailed,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: TsPhoneSpacing.medium),
                  IconButton.filledTonal(
                    key: const ValueKey<String>('markdown-image-retry'),
                    onPressed: onRetry,
                    tooltip: context.l10n.retry,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openHttpsUri(Uri uri) async {
  if (uri.scheme != 'https') return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class InlineCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(
        maxWidth: (MediaQuery.sizeOf(context).width - 64)
            .clamp(80, 720)
            .toDouble(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.outlineVariant, width: 0.5),
      ),
      child: Text(
        element.textContent,
        softWrap: true,
        style: (preferredStyle ?? parentStyle)?.copyWith(
          color: colors.onSurface,
          backgroundColor: Colors.transparent,
          fontFamily: 'monospace',
          letterSpacing: 0,
          height: 1.35,
        ),
      ),
    );
  }
}

class TerminalMarkdownBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final languageClass = code?.attributes['class'];
    final language = languageClass?.startsWith('language-') == true
        ? languageClass!.substring('language-'.length)
        : null;
    return TsTerminalBlock(
      title: language?.isNotEmpty == true ? language : null,
      body: element.textContent.trimRight(),
    );
  }
}

class InlineMathSyntax extends md.InlineSyntax {
  InlineMathSyntax() : super(r'\$(?!\$)([^\n\$]+)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (parser.pos > 0 && parser.source.codeUnitAt(parser.pos - 1) == 0x5c) {
      return false;
    }
    parser.addNode(md.Element.text('math-inline', match[1]!));
    return true;
  }
}

class BlockMathSyntax extends md.BlockSyntax {
  const BlockMathSyntax();

  @override
  RegExp get pattern => RegExp(r'^ {0,3}\$\$\s*$');

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final lines = <String>[];
    while (!parser.isDone && !pattern.hasMatch(parser.current.content)) {
      lines.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) {
      parser.advance();
    }
    return md.Element.text('math-block', lines.join('\n'));
  }
}

class MathBuilder extends MarkdownElementBuilder {
  MathBuilder({required this.isBlock});

  final bool isBlock;

  @override
  bool isBlockElement() => isBlock;

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final math = Math.tex(
      element.textContent,
      mathStyle: isBlock ? MathStyle.display : MathStyle.text,
      textStyle: preferredStyle,
      onErrorFallback: (error) => SelectableText(element.textContent),
    );
    if (!isBlock) return math;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: math,
    );
  }
}
