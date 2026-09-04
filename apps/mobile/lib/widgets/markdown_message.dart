import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations_extensions.dart';
import '../theme/ts_phone_theme.dart';
import 'presentation.dart';

class MarkdownMessage extends StatelessWidget {
  const MarkdownMessage({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = TsPhoneStatusTheme.resolve(context);
    return MarkdownBody(
      data: data,
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
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton.outlined(
        onPressed: () => _openLink(uri.toString()),
        tooltip: alt?.isNotEmpty == true
            ? context.l10n.openImageWithAlt(alt!)
            : context.l10n.openImage,
        icon: const Icon(Icons.image_outlined),
      ),
    );
  }

  Future<void> _openLink(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || uri.scheme != 'https') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
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
