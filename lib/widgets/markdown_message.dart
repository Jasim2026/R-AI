import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import '../utils/theme.dart';

class MarkdownMessage extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isStreaming;

  const MarkdownMessage({
    super.key,
    required this.content,
    required this.isUser,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isUser) {
      return SelectableText(
        content,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.55,
        ),
      );
    }

    return MarkdownBody(
      data: content,
      selectable: true,
      markdownStyleSheet: _buildStyleSheet(context),
      builders: {
        'pre': _CodeBlockBuilder(),
      },
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [
        LatexInlineSyntax(),
      ],
      builders: {
        'latex': LatexElementBuilder(),
        'pre': _CodeBlockBuilder(),
      },
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    return MarkdownStyleSheet(
      p: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
        height: 1.6,
      ),
      strong: const TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      em: const TextStyle(
        color: AppColors.textPrimary,
        fontStyle: FontStyle.italic,
      ),
      code: const TextStyle(
        color: AppColors.primary,
        fontSize: 13,
        fontFamily: 'monospace',
        backgroundColor: AppColors.surfaceDark,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      h1: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      h2: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      h3: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      blockquote: const TextStyle(
        color: AppColors.textSecondary,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AppColors.primary.withOpacity(0.5),
            width: 3,
          ),
        ),
      ),
      listBullet: const TextStyle(
        color: AppColors.textPrimary,
      ),
      listIndent: 24,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.divider,
            width: 1,
          ),
        ),
      ),
      tableHead: const TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      tableBody: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
      ),
      tableBorder: TableBorder.all(
        color: AppColors.divider,
        width: 0.5,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;
    final lines = code.split('\n');
    final language = lines.firstWhere(
      (line) => line.trim().isNotEmpty,
      orElse: () => '',
    );

    final codeContent = lines.length > 1 ? lines.sublist(1).join('\n') : code;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (language.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Text(
                language,
                style: TextStyle(
                  color: AppColors.primary.withOpacity(0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              codeContent,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
