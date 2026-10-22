import 'package:flutter/material.dart';

const sinhalaTextStyle = TextStyle(
  fontFamily: 'NotoSansSinhala',
  fontSize: 22,
  height: 1.7,
  letterSpacing: 0,
  wordSpacing: 0,
  fontWeight: FontWeight.w400,
  locale: Locale('si', 'LK'),
);

class SinhalaText extends StatelessWidget {
  const SinhalaText(this.text, {super.key, this.maxLines, this.fontSize = 22});
  final String text;
  final int? maxLines;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final style = sinhalaTextStyle.copyWith(fontSize: fontSize);
    if (maxLines != null) {
      return Text(
        text.trim(),
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.ltr,
      );
    }
    return SelectableText(
      text.trim(),
      style: style,
      textDirection: TextDirection.ltr,
    );
  }
}
