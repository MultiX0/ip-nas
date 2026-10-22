// Arabic-first helpers: pick text direction per message from its first strong character.
import 'package:flutter/widgets.dart';

final _rtl = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]');
final _ltr = RegExp(r'[A-Za-zÀ-ɏͰ-ϿЀ-ӿ]');

TextDirection textDirOf(String s) {
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (_rtl.hasMatch(c)) return TextDirection.rtl;
    if (_ltr.hasMatch(c)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

bool isArabic(String s) => textDirOf(s) == TextDirection.rtl;
