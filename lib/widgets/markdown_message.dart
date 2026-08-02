import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
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
        style: AppColors.font(size: 14, height: 1.5),
      );
    }

    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: _buildStyleSheet(context),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {
        'pre': _CodeBlockBuilder(),
      },
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    return MarkdownStyleSheet(
      p: AppColors.font(size: 14, height: 1.6),
      strong: AppColors.font(size: 14, weight: FontWeight.w700, height: 1.6),
      em: AppColors.font(
        size: 14,
        height: 1.6,
      ),
      code: GoogleFonts.jetBrainsMono(
        color: AppColors.primary,
        fontSize: 12,
        backgroundColor: AppColors.surfaceLight,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      h1: AppColors.font(size: 20, weight: FontWeight.w700, height: 1.3),
      h2: AppColors.font(size: 17, weight: FontWeight.w600, height: 1.3),
      h3: AppColors.font(size: 15, weight: FontWeight.w600, height: 1.3),
      blockquote: AppColors.font(
        size: 14,
        color: AppColors.textSecondary,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AppColors.primary.withOpacity(0.4),
            width: 2,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
      listBullet: AppColors.font(size: 14, color: AppColors.textSecondary),
      listIndent: 20,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      tableHead: AppColors.font(
        size: 13,
        weight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
      tableBody: AppColors.font(size: 13),
      tableBorder: TableBorder.all(
        color: AppColors.divider,
        width: 0.5,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;
    final lines = code.split('\n');

    String language = '';
    String codeContent = code;

    if (lines.length > 1) {
      final firstLine = lines.first.trim();
      if (firstLine.isNotEmpty && !_isCode(firstLine)) {
        language = firstLine;
        codeContent = lines.sublist(1).join('\n').trim();
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    language,
                    style: GoogleFonts.jetBrainsMono(
                      color: AppColors.primary.withOpacity(0.7),
                      fontSize: 10,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              codeContent,
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.textPrimary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isCode(String text) {
    // Heuristic: if it looks like a programming statement, it's code
    final codePatterns = RegExp(r'[{}\[\]();=<>]');
    return codePatterns.hasMatch(text);
  }
}
