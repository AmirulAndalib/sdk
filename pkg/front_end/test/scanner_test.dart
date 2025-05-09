// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/base/errors.dart';
import 'package:_fe_analyzer_shared/src/scanner/abstract_scanner.dart'
    show AbstractScanner, ScannerConfiguration;
import 'package:_fe_analyzer_shared/src/scanner/errors.dart';
import 'package:_fe_analyzer_shared/src/scanner/reader.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CharSequenceReaderTest);
    defineReflectiveTests(TokenTypeTest);
  });
}

@reflectiveTest
class CharSequenceReaderTest {
  void test_advance() {
    CharSequenceReader reader = new CharSequenceReader("x");
    expect(reader.advance(), 0x78);
    expect(reader.advance(), -1);
    expect(reader.advance(), -1);
  }

  void test_creation() {
    expect(new CharSequenceReader("x"), isNotNull);
  }

  void test_getOffset() {
    CharSequenceReader reader = new CharSequenceReader("x");
    expect(reader.offset, -1);
    reader.advance();
    expect(reader.offset, 0);
    reader.advance();
    expect(reader.offset, 0);
  }

  void test_getString() {
    CharSequenceReader reader = new CharSequenceReader("xyzzy");
    reader.offset = 3;
    expect(reader.getString(1, 0), "yzz");
    expect(reader.getString(2, 1), "zzy");
  }

  void test_peek() {
    CharSequenceReader reader = new CharSequenceReader("xy");
    expect(reader.peek(), 0x78);
    expect(reader.peek(), 0x78);
    reader.advance();
    expect(reader.peek(), 0x79);
    expect(reader.peek(), 0x79);
    reader.advance();
    expect(reader.peek(), -1);
    expect(reader.peek(), -1);
  }

  void test_setOffset() {
    CharSequenceReader reader = new CharSequenceReader("xyz");
    reader.offset = 2;
    expect(reader.offset, 2);
  }
}

class ErrorListener {
  final errors = <TestError>[];

  void assertErrors(List<TestError> expectedErrors) {
    expect(errors, unorderedEquals(expectedErrors));
  }

  void assertNoErrors() {
    assertErrors([]);
  }
}

abstract class ScannerTestBase {
  Token scanWithListener(String source, ErrorListener listener,
      {ScannerConfiguration? configuration});

  void test_ampersand() {
    _assertToken(TokenType.AMPERSAND, "&");
  }

  void test_ampersand_ampersand() {
    _assertToken(TokenType.AMPERSAND_AMPERSAND, "&&");
  }

  void test_ampersand_ampersand_eq() {
    if (AbstractScanner.LAZY_ASSIGNMENT_ENABLED) {
      _assertToken(TokenType.AMPERSAND_AMPERSAND_EQ, "&&=");
    }
  }

  void test_ampersand_eq() {
    _assertToken(TokenType.AMPERSAND_EQ, "&=");
  }

  void test_angle_brackets() {
    var lessThan = _scan('<String>');
    var identifier = lessThan.next!;
    var greaterThan = identifier.next!;
    expect(greaterThan.next!.type, TokenType.EOF);
    // Analyzer's token streams don't consider "<" to be an opener
    // but the scanner does.
    if (lessThan is BeginToken) {
      expect(lessThan.endToken, greaterThan);
    }
    expect(greaterThan, isNot(const TypeMatcher<BeginToken>()));
  }

  void test_async_star() {
    Token token = _scan("async*");
    expect(token.type.isKeyword, true);
    expect(token.lexeme, 'async');
    expect(token.next!.type, TokenType.STAR);
    expect(token.next!.next!.type, TokenType.EOF);
  }

  void test_at() {
    _assertToken(TokenType.AT, "@");
  }

  void test_backping() {
    _assertToken(TokenType.BACKPING, "`");
  }

  void test_backslash() {
    _assertToken(TokenType.BACKSLASH, "\\");
  }

  void test_bang() {
    _assertToken(TokenType.BANG, "!");
  }

  void test_bang_eq() {
    _assertToken(TokenType.BANG_EQ, "!=");
  }

  void test_bar() {
    _assertToken(TokenType.BAR, "|");
  }

  void test_bar_bar() {
    _assertToken(TokenType.BAR_BAR, "||");
  }

  void test_bar_bar_eq() {
    if (AbstractScanner.LAZY_ASSIGNMENT_ENABLED) {
      _assertToken(TokenType.BAR_BAR_EQ, "||=");
    }
  }

  void test_bar_eq() {
    _assertToken(TokenType.BAR_EQ, "|=");
  }

  void test_caret() {
    _assertToken(TokenType.CARET, "^");
  }

  void test_caret_eq() {
    _assertToken(TokenType.CARET_EQ, "^=");
  }

  void test_close_curly_bracket() {
    _assertToken(TokenType.CLOSE_CURLY_BRACKET, "}");
  }

  void test_close_paren() {
    _assertToken(TokenType.CLOSE_PAREN, ")");
  }

  void test_close_quare_bracket() {
    _assertToken(TokenType.CLOSE_SQUARE_BRACKET, "]");
  }

  void test_colon() {
    _assertToken(TokenType.COLON, ":");
  }

  void test_comma() {
    _assertToken(TokenType.COMMA, ",");
  }

  void test_comment_multi() {
    _assertComment(TokenType.MULTI_LINE_COMMENT, "/* comment */");
  }

  void test_comment_multi_consecutive_2() {
    Token token = _scan("/* x */ /* y */ z");
    expect(token.type, TokenType.IDENTIFIER);
    expect(token.precedingComments, isNotNull);
    expect(token.precedingComments!.value(), "/* x */");
    expect(token.precedingComments!.previous, isNull);
    expect(token.precedingComments!.next, isNotNull);
    expect(token.precedingComments!.next!.value(), "/* y */");
    expect(
        token.precedingComments!.next!.previous, same(token.precedingComments));
    expect(token.precedingComments!.next!.next, isNull);
  }

  void test_comment_multi_consecutive_3() {
    Token token = _scan("/* x */ /* y */ /* z */ a");
    expect(token.type, TokenType.IDENTIFIER);
    expect(token.precedingComments, isNotNull);
    expect(token.precedingComments!.value(), "/* x */");
    expect(token.precedingComments!.previous, isNull);
    expect(token.precedingComments!.next, isNotNull);
    expect(token.precedingComments!.next!.value(), "/* y */");
    expect(
        token.precedingComments!.next!.previous, same(token.precedingComments));
    expect(token.precedingComments!.next!.next, isNotNull);
    expect(token.precedingComments!.next!.next!.value(), "/* z */");
    expect(token.precedingComments!.next!.next!.previous,
        same(token.precedingComments!.next));
    expect(token.precedingComments!.next!.next!.next, isNull);
  }

  void test_comment_multi_unterminated() {
    _assertError(ScannerErrorCode.UNTERMINATED_MULTI_LINE_COMMENT, 3, "/* x");
  }

  void test_comment_nested() {
    _assertComment(
        TokenType.MULTI_LINE_COMMENT, "/* comment /* within a */ comment */");
  }

  void test_comment_single() {
    _assertComment(TokenType.SINGLE_LINE_COMMENT, "// comment");
  }

  void test_double_both_E() {
    _assertToken(TokenType.DOUBLE, "0.123E4");
  }

  void test_double_both_e() {
    _assertToken(TokenType.DOUBLE, "0.123e4");
  }

  void test_double_both_e_separatorInExponent() {
    _assertToken(TokenType.DOUBLE_WITH_SEPARATORS, "0.123e0_4");
  }

  void test_double_both_e_separatorInBase() {
    _assertToken(TokenType.DOUBLE_WITH_SEPARATORS, "0.123_0e4");
  }

  void test_double_fraction() {
    _assertToken(TokenType.DOUBLE, ".123");
  }

  void test_double_fraction_E() {
    _assertToken(TokenType.DOUBLE, ".123E4");
  }

  void test_double_fraction_e() {
    _assertToken(TokenType.DOUBLE, ".123e4");
  }

  void test_double_missingDigitInExponent() {
    _assertError(ScannerErrorCode.MISSING_DIGIT, 1, "1e");
  }

  void test_double_whole_E() {
    _assertToken(TokenType.DOUBLE, "12E4");
  }

  void test_double_whole_e() {
    _assertToken(TokenType.DOUBLE, "12e4");
  }

  void test_double_whole_e_separatorInBase() {
    _assertToken(TokenType.DOUBLE_WITH_SEPARATORS, "1_2e4");
  }

  void test_double_whole_e_separatorInExponent() {
    _assertToken(TokenType.DOUBLE_WITH_SEPARATORS, "12e0_4");
  }

  void test_eq() {
    _assertToken(TokenType.EQ, "=");
  }

  void test_eq_eq() {
    _assertToken(TokenType.EQ_EQ, "==");
  }

  void test_function() {
    _assertToken(TokenType.FUNCTION, "=>");
  }

  void test_gt() {
    _assertToken(TokenType.GT, ">");
  }

  void test_gt_eq() {
    _assertToken(TokenType.GT_EQ, ">=");
  }

  void test_gt_gt() {
    _assertToken(TokenType.GT_GT, ">>");
  }

  void test_gt_gt_eq() {
    _assertToken(TokenType.GT_GT_EQ, ">>=");
  }

  void test_hash() {
    _assertToken(TokenType.HASH, "#");
  }

  void test_hexadecimal() {
    _assertToken(TokenType.HEXADECIMAL, "0x1A2B3C");
  }

  void test_hexadecimal_separators() {
    _assertToken(TokenType.HEXADECIMAL_WITH_SEPARATORS, "0x1A_2B_3C");
  }

  void test_hexadecimal_missingDigit() {
    var token = _assertError(ScannerErrorCode.MISSING_HEX_DIGIT, 5, "a = 0x");
    expect(token.lexeme, 'a');
    token = token.next!;
    expect(token.lexeme, '=');
    token = token.next!;
    expect(token.lexeme, '0x0');
  }

  void test_hexadecimal_unexpectedSeparator() {
    var token = _assertError(
        ScannerErrorCode.UNEXPECTED_SEPARATOR_IN_NUMBER,
        // TODO(srawlins): Should be 5?
        4,
        "a = 0x5_");
    expect(token.lexeme, 'a');
    token = token.next!;
    expect(token.lexeme, '=');
    token = token.next!;
    expect(token.lexeme, '0x5_');
  }

  void test_identifier() {
    _assertToken(TokenType.IDENTIFIER, "result");
  }

  void test_illegalChar_cyrillicLetter_middle() {
    final identifier = "Shche\u0433lov";
    final token = _assertError(
        ScannerErrorCode.ILLEGAL_CHARACTER, 5, identifier, [0x433]);
    expect(token.type, TokenType.IDENTIFIER);
    expect(token.lexeme, identifier);
  }

  void test_illegalChar_cyrillicLetter_multiple() {
    ErrorListener listener = new ErrorListener();
    var tokens = scanWithListener("a = Shche\u0433lov\u0429x;", listener);
    listener.assertErrors([
      new TestError(9, ScannerErrorCode.ILLEGAL_CHARACTER, [0x433]),
      new TestError(13, ScannerErrorCode.ILLEGAL_CHARACTER, [0x429]),
    ]);
    var token = tokens;
    expect(token.lexeme, 'a');
    token = token.next!;
    expect(token.lexeme, '=');
    token = token.next!;
    expect(token.type, TokenType.IDENTIFIER);
    expect(token.lexeme, "Shche\u0433lov\u0429x");
    token = token.next!;
    expect(token.lexeme, ';');
  }

  void test_illegalChar_cyrillicLetter_start() {
    final identifier = "\u0429";
    final token = _assertError(
        ScannerErrorCode.ILLEGAL_CHARACTER, 0, identifier, [0x429]);
    expect(token.type, TokenType.IDENTIFIER);
    expect(token.lexeme, identifier);
  }

  void test_illegalChar_cyrillicLetter_start_expression() {
    var token = _assertError(
        ScannerErrorCode.ILLEGAL_CHARACTER, 4, 'a = \u0429;', [0x429]);
    expect(token.lexeme, 'a');
    token = token.next!;
    expect(token.lexeme, '=');
    token = token.next!;
    expect(token.type, TokenType.IDENTIFIER);
    expect(token.lexeme, "\u0429");
    token = token.next!;
    expect(token.lexeme, ';');
  }

  void test_illegalChar_nbsp() {
    _assertError(ScannerErrorCode.ILLEGAL_CHARACTER, 0, "\u00A0", [0xa0]);
  }

  void test_illegalChar_notLetter() {
    _assertError(ScannerErrorCode.ILLEGAL_CHARACTER, 0, "\u0312", [0x312]);
  }

  void test_incomplete_string_interpolation() {
    // https://code.google.com/p/dart/issues/detail?id=18073
    List<Token> expectedTokens = [
      new StringToken(TokenType.STRING, "\"foo ", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_EXPRESSION, "\${", 5),
      new StringToken(TokenType.IDENTIFIER, "bar", 7),
    ];
    var expectedErrors = [
      new TestError(9, ScannerErrorCode.UNTERMINATED_STRING_LITERAL, null),
    ];
    // The scanner inserts synthetic closers
    expectedTokens.addAll([
      new SyntheticToken(TokenType.CLOSE_CURLY_BRACKET, 10),
      new SyntheticStringToken(TokenType.STRING, "\"", 10, 0),
    ]);
    expectedErrors.addAll([
      new TestError(10, ScannerErrorCode.EXPECTED_TOKEN, ['}']),
    ]);
    ErrorListener listener = new ErrorListener();
    Token token = scanWithListener("\"foo \${bar", listener);
    listener.assertErrors(expectedErrors);
    _checkTokens(token, expectedTokens);
  }

  void test_index() {
    _assertToken(TokenType.INDEX, "[]");
  }

  void test_index_eq() {
    _assertToken(TokenType.INDEX_EQ, "[]=");
  }

  void test_int() {
    _assertToken(TokenType.INT, "123");
  }

  void test_int_separators() {
    _assertToken(TokenType.INT_WITH_SEPARATORS, "123_456_789");
  }

  void test_int_separators_bad() {
    _assertToken(TokenType.INT_WITH_SEPARATORS, "123_");
  }

  void test_int_initialZero() {
    _assertToken(TokenType.INT, "0123");
  }

  void test_keyword_abstract() {
    _assertKeywordToken("abstract");
  }

  void test_keyword_as() {
    _assertKeywordToken("as");
  }

  void test_keyword_assert() {
    _assertKeywordToken("assert");
  }

  void test_keyword_async() {
    _assertKeywordToken("async");
  }

  void test_keyword_await() {
    _assertKeywordToken("await");
  }

  void test_keyword_break() {
    _assertKeywordToken("break");
  }

  void test_keyword_case() {
    _assertKeywordToken("case");
  }

  void test_keyword_catch() {
    _assertKeywordToken("catch");
  }

  void test_keyword_class() {
    _assertKeywordToken("class");
  }

  void test_keyword_const() {
    _assertKeywordToken("const");
  }

  void test_keyword_continue() {
    _assertKeywordToken("continue");
  }

  void test_keyword_default() {
    _assertKeywordToken("default");
  }

  void test_keyword_deferred() {
    _assertKeywordToken("deferred");
  }

  void test_keyword_do() {
    _assertKeywordToken("do");
  }

  void test_keyword_dynamic() {
    _assertKeywordToken("dynamic");
  }

  void test_keyword_else() {
    _assertKeywordToken("else");
  }

  void test_keyword_enum() {
    _assertKeywordToken("enum");
  }

  void test_keyword_export() {
    _assertKeywordToken("export");
  }

  void test_keyword_extends() {
    _assertKeywordToken("extends");
  }

  void test_keyword_extension() {
    _assertKeywordToken("extension", configuration: ScannerConfiguration());
  }

  void test_keyword_factory() {
    _assertKeywordToken("factory");
  }

  void test_keyword_false() {
    _assertKeywordToken("false");
  }

  void test_keyword_final() {
    _assertKeywordToken("final");
  }

  void test_keyword_finally() {
    _assertKeywordToken("finally");
  }

  void test_keyword_for() {
    _assertKeywordToken("for");
  }

  void test_keyword_get() {
    _assertKeywordToken("get");
  }

  void test_keyword_hide() {
    _assertKeywordToken("hide");
  }

  void test_keyword_if() {
    _assertKeywordToken("if");
  }

  void test_keyword_implements() {
    _assertKeywordToken("implements");
  }

  void test_keyword_interface() {
    _assertKeywordToken("interface");
  }

  void test_keyword_import() {
    _assertKeywordToken("import");
  }

  void test_keyword_in() {
    _assertKeywordToken("in");
  }

  void test_keyword_inout() {
    _assertKeywordToken("inout");
  }

  void test_keyword_is() {
    _assertKeywordToken("is");
  }

  void test_keyword_late() {
    _assertKeywordToken("late", configuration: ScannerConfiguration());
  }

  void test_keyword_library() {
    _assertKeywordToken("library");
  }

  void test_keyword_mixin() {
    _assertKeywordToken("mixin");
  }

  void test_keyword_native() {
    _assertKeywordToken("native");
  }

  void test_keyword_new() {
    _assertKeywordToken("new");
  }

  void test_keyword_null() {
    _assertKeywordToken("null");
  }

  void test_keyword_of() {
    _assertKeywordToken("of");
  }

  void test_keyword_on() {
    _assertKeywordToken("on");
  }

  void test_keyword_operator() {
    _assertKeywordToken("operator");
  }

  void test_keyword_out() {
    _assertKeywordToken("out");
  }

  void test_keyword_part() {
    _assertKeywordToken("part");
  }

  void test_keyword_patch() {
    _assertKeywordToken("patch");
  }

  void test_keyword_required() {
    _assertKeywordToken("required", configuration: ScannerConfiguration());
  }

  void test_keyword_rethrow() {
    _assertKeywordToken("rethrow");
  }

  void test_keyword_return() {
    _assertKeywordToken("return");
  }

  void test_keyword_set() {
    _assertKeywordToken("set");
  }

  void test_keyword_show() {
    _assertKeywordToken("show");
  }

  void test_keyword_source() {
    _assertKeywordToken("source");
  }

  void test_keyword_static() {
    _assertKeywordToken("static");
  }

  void test_keyword_super() {
    _assertKeywordToken("super");
  }

  void test_keyword_switch() {
    _assertKeywordToken("switch");
  }

  void test_keyword_sync() {
    _assertKeywordToken("sync");
  }

  void test_keyword_this() {
    _assertKeywordToken("this");
  }

  void test_keyword_throw() {
    _assertKeywordToken("throw");
  }

  void test_keyword_true() {
    _assertKeywordToken("true");
  }

  void test_keyword_try() {
    _assertKeywordToken("try");
  }

  void test_keyword_typedef() {
    _assertKeywordToken("typedef");
  }

  void test_keyword_var() {
    _assertKeywordToken("var");
  }

  void test_keyword_void() {
    _assertKeywordToken("void");
  }

  void test_keyword_while() {
    _assertKeywordToken("while");
  }

  void test_keyword_with() {
    _assertKeywordToken("with");
  }

  void test_keyword_yield() {
    _assertKeywordToken("yield");
  }

  void test_lt() {
    _assertToken(TokenType.LT, "<");
  }

  void test_lt_eq() {
    _assertToken(TokenType.LT_EQ, "<=");
  }

  void test_lt_lt() {
    _assertToken(TokenType.LT_LT, "<<");
  }

  void test_lt_lt_eq() {
    _assertToken(TokenType.LT_LT_EQ, "<<=");
  }

  void test_matching_braces() {
    BeginToken openBrace1 = _scan('{1: {2: 3}}') as BeginToken;
    var one = openBrace1.next!;
    var colon1 = one.next!;
    BeginToken openBrace2 = colon1.next as BeginToken;
    var two = openBrace2.next!;
    var colon2 = two.next!;
    var three = colon2.next!;
    var closeBrace1 = three.next!;
    var closeBrace2 = closeBrace1.next!;
    expect(closeBrace2.next!.type, TokenType.EOF);
    expect(openBrace1.endToken, same(closeBrace2));
    expect(openBrace2.endToken, same(closeBrace1));
  }

  void test_matching_brackets() {
    BeginToken openBracket1 = _scan('[1, [2]]') as BeginToken;
    var one = openBracket1.next!;
    var comma = one.next!;
    BeginToken openBracket2 = comma.next as BeginToken;
    var two = openBracket2.next!;
    var closeBracket1 = two.next!;
    var closeBracket2 = closeBracket1.next!;
    expect(closeBracket2.next!.type, TokenType.EOF);
    expect(openBracket1.endToken, same(closeBracket2));
    expect(openBracket2.endToken, same(closeBracket1));
  }

  void test_matching_parens() {
    BeginToken openParen1 = _scan('(f(x))') as BeginToken;
    var f = openParen1.next!;
    BeginToken openParen2 = f.next as BeginToken;
    var x = openParen2.next!;
    var closeParen1 = x.next!;
    var closeParen2 = closeParen1.next!;
    expect(closeParen2.next!.type, TokenType.EOF);
    expect(openParen1.endToken, same(closeParen2));
    expect(openParen2.endToken, same(closeParen1));
  }

  void test_minus() {
    _assertToken(TokenType.MINUS, "-");
  }

  void test_minus_eq() {
    _assertToken(TokenType.MINUS_EQ, "-=");
  }

  void test_minus_minus() {
    _assertToken(TokenType.MINUS_MINUS, "--");
  }

  void test_mismatched_closer() {
    // Normally when openers and closers are mismatched
    // the scanner favors considering the opener to be mismatched,
    // and inserts synthetic closers as needed.
    // In this particular case, the scanner cannot find an opener for ']'
    // and thus marks ']' as an error and moves on.
    ErrorListener listener = new ErrorListener();
    BeginToken openParen = scanWithListener('(])', listener) as BeginToken;
    var closeBracket = openParen.next!;
    var closeParen = closeBracket.next!;
    expect(closeParen.next!.type, TokenType.EOF);
    expect(openParen.endToken, same(closeParen));
    listener.assertNoErrors();
  }

  void test_mismatched_closer2() {
    // When openers and closers are mismatched, the scanner has two options:
    // * If there is a matching opener on the stack it can create fake closers
    //   for everything up til there, or
    // * It can treat the closer as a non-closer (basically ignore that it's a
    //   closer).
    // The scanner tries both options to see which is better (leads to fewest
    // rewrites later) and picks that strategy.
    // Example: `[(])` can be scanned in 2 ways:
    // 1) `[()])` where the first `)` is synthetic and the last `)` is
    //    ignored/unmatched (i.e. 2 recoveries).
    // 2) `[(])` where `]` is ignored/unmatched and `[` is unmatched (i.e.
    //    2 recoveries).
    // Both options are "equally bad" and the first choise is made.
    ErrorListener listener = new ErrorListener();
    BeginToken openBracket = scanWithListener('[(])', listener) as BeginToken;
    BeginToken openParen = openBracket.next as BeginToken;
    var closeParen = openParen.next!;
    expect(closeParen.isSynthetic, isTrue);
    var closeBracket = closeParen.next!;
    expect(closeBracket.isSynthetic, isFalse);
    var closeParen2 = closeBracket.next!;
    expect(closeParen2.isSynthetic, isFalse);
    expect(closeParen2.next!.type, TokenType.EOF);
    expect(openBracket.endToken, same(closeBracket));
    expect(openParen.endToken, same(closeParen));
    listener.assertErrors([
      new TestError(2, ScannerErrorCode.EXPECTED_TOKEN, [')']),
    ]);
  }

  void test_mismatched_opener() {
    // When openers and closers are mismatched, analyzer favors considering the
    // closer to be mismatched, which means that `([)` parses as three unmatched
    // tokens.
    ErrorListener listener = new ErrorListener();
    BeginToken openParen = scanWithListener('([)', listener) as BeginToken;
    BeginToken openBracket = openParen.next as BeginToken;
    // When openers and closers are mismatched,
    // the scanner favors considering the opener to be mismatched
    // and inserts synthetic closers as needed.
    // `([)` is scanned as `([])` where `]` is synthetic.
    var closeBracket = openBracket.next!;
    expect(closeBracket.isSynthetic, isTrue);
    var closeParen = closeBracket.next!;
    expect(closeParen.isSynthetic, isFalse);
    expect(closeParen.next!.type, TokenType.EOF);
    expect(openBracket.endToken, closeBracket);
    expect(openParen.endToken, closeParen);
    listener.assertErrors([
      new TestError(2, ScannerErrorCode.EXPECTED_TOKEN, [']']),
    ]);
  }

  void test_mismatched_opener_in_interpolation() {
    // In an interpolation expression, analyzer considers a closing `}` to
    // always match the preceding unmatched `{`, even if there are intervening
    // unmatched tokens, which means that `"${({(}}"` parses as though the open
    // parens are unmatched but everything else is matched.
    var stringStart = _scan(r'"${({(}}"');
    BeginToken interpolationStart = stringStart.next as BeginToken;
    BeginToken openParen1 = interpolationStart.next as BeginToken;
    BeginToken openBrace = openParen1.next as BeginToken;
    BeginToken openParen2 = openBrace.next as BeginToken;
    var closeBrace = openParen2.next!;
    var interpolationEnd = closeBrace.next!;
    var stringEnd = interpolationEnd.next!;
    expect(stringEnd.next!.type, TokenType.EOF);
    expect(interpolationStart.endToken, same(interpolationEnd));
    expect(openParen1.endToken, isNull);
    expect(openBrace.endToken, same(closeBrace));
    expect(openParen2.endToken, isNull);
  }

  void test_open_curly_bracket() {
    _assertToken(TokenType.OPEN_CURLY_BRACKET, "{");
  }

  void test_open_paren() {
    _assertToken(TokenType.OPEN_PAREN, "(");
  }

  void test_open_square_bracket() {
    _assertToken(TokenType.OPEN_SQUARE_BRACKET, "[");
  }

  void test_percent() {
    _assertToken(TokenType.PERCENT, "%");
  }

  void test_percent_eq() {
    _assertToken(TokenType.PERCENT_EQ, "%=");
  }

  void test_period() {
    _assertToken(TokenType.PERIOD, ".");
  }

  void test_period_period() {
    _assertToken(TokenType.PERIOD_PERIOD, "..");
  }

  void test_period_period_period() {
    _assertToken(TokenType.PERIOD_PERIOD_PERIOD, "...");
  }

  void test_periodAfterNumberNotIncluded_identifier() {
    _assertTokens("42.isEven()", [
      new StringToken(TokenType.INT, "42", 0),
      new Token(TokenType.PERIOD, 2),
      new StringToken(TokenType.IDENTIFIER, "isEven", 3),
      new Token(TokenType.OPEN_PAREN, 9),
      new Token(TokenType.CLOSE_PAREN, 10)
    ]);
  }

  void test_periodAfterNumberNotIncluded_period() {
    _assertTokens("42..isEven()", [
      new StringToken(TokenType.INT, "42", 0),
      new Token(TokenType.PERIOD_PERIOD, 2),
      new StringToken(TokenType.IDENTIFIER, "isEven", 4),
      new Token(TokenType.OPEN_PAREN, 10),
      new Token(TokenType.CLOSE_PAREN, 11)
    ]);
  }

  void test_plus() {
    _assertToken(TokenType.PLUS, "+");
  }

  void test_plus_eq() {
    _assertToken(TokenType.PLUS_EQ, "+=");
  }

  void test_plus_plus() {
    _assertToken(TokenType.PLUS_PLUS, "++");
  }

  void test_question() {
    _assertToken(TokenType.QUESTION, "?");
  }

  void test_question_dot() {
    _assertToken(TokenType.QUESTION_PERIOD, "?.");
  }

  void test_question_question() {
    _assertToken(TokenType.QUESTION_QUESTION, "??");
  }

  void test_question_question_eq() {
    _assertToken(TokenType.QUESTION_QUESTION_EQ, "??=");
  }

  void test_scriptTag_withArgs() {
    _assertToken(TokenType.SCRIPT_TAG, "#!/bin/dart -debug");
  }

  void test_scriptTag_withoutSpace() {
    _assertToken(TokenType.SCRIPT_TAG, "#!/bin/dart");
  }

  void test_scriptTag_withSpace() {
    _assertToken(TokenType.SCRIPT_TAG, "#! /bin/dart");
  }

  void test_semicolon() {
    _assertToken(TokenType.SEMICOLON, ";");
  }

  void test_slash() {
    _assertToken(TokenType.SLASH, "/");
  }

  void test_slash_eq() {
    _assertToken(TokenType.SLASH_EQ, "/=");
  }

  void test_star() {
    _assertToken(TokenType.STAR, "*");
  }

  void test_star_eq() {
    _assertToken(TokenType.STAR_EQ, "*=");
  }

  void test_startAndEnd() {
    Token token = _scan("a");
    expect(token.offset, 0);
    Token previous = token.previous!;
    expect(previous.next, token);
    expect(previous.previous, previous);
    expect(previous.type, TokenType.EOF);
    expect(previous.offset, -1);
    Token next = token.next!;
    expect(next.next, next);
    expect(next.previous, token);
    expect(next.type, TokenType.EOF);
    expect(next.offset, token.offset + token.length);
  }

  void test_string_multi_double() {
    _assertToken(TokenType.STRING, "\"\"\"line1\nline2\"\"\"");
  }

  void test_string_multi_embeddedQuotes() {
    _assertToken(TokenType.STRING, "\"\"\"line1\n\"\"\nline2\"\"\"");
  }

  void test_string_multi_embeddedQuotes_escapedChar() {
    _assertToken(TokenType.STRING, "\"\"\"a\"\"\\tb\"\"\"");
  }

  void test_string_multi_interpolation_block() {
    _assertTokens("\"Hello \${name}!\"", [
      new StringToken(TokenType.STRING, "\"Hello ", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_EXPRESSION, "\${", 7),
      new StringToken(TokenType.IDENTIFIER, "name", 9),
      new Token(TokenType.CLOSE_CURLY_BRACKET, 13),
      new StringToken(TokenType.STRING, "!\"", 14)
    ]);
  }

  void test_string_multi_interpolation_identifier() {
    _assertTokens("\"Hello \$name!\"", [
      new StringToken(TokenType.STRING, "\"Hello ", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 7),
      new StringToken(TokenType.IDENTIFIER, "name", 8),
      new StringToken(TokenType.STRING, "!\"", 12)
    ]);
  }

  void test_string_multi_single() {
    _assertToken(TokenType.STRING, "'''string'''");
  }

  void test_string_multi_slashEnter() {
    _assertToken(TokenType.STRING, "'''\\\n'''");
  }

  void test_string_multi_unterminated() {
    List<Token> expectedTokens = [];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.STRING, "'''string'''", 0, 9),
    ]);
  }

  void test_string_multi_unterminated_interpolation_block() {
    List<Token> expectedTokens = [
      new StringToken(TokenType.STRING, "'''", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_EXPRESSION, "\${", 3),
      new StringToken(TokenType.IDENTIFIER, "name", 5),
    ];
    var expectedErrors = [
      new TestError(8, ScannerErrorCode.UNTERMINATED_STRING_LITERAL, null),
    ];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticToken(TokenType.CLOSE_CURLY_BRACKET, 9),
      new SyntheticStringToken(TokenType.STRING, "'''", 9, 0),
    ]);
    expectedErrors.addAll([
      new TestError(9, ScannerErrorCode.EXPECTED_TOKEN, ['}']),
    ]);
    ErrorListener listener = new ErrorListener();
    Token token = scanWithListener("'''\${name", listener);
    listener.assertErrors(expectedErrors);
    _checkTokens(token, expectedTokens);
  }

  void test_string_multi_unterminated_interpolation_identifier() {
    List<Token> expectedTokens = [
      new StringToken(TokenType.STRING, "'''", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 3),
      new StringToken(TokenType.IDENTIFIER, "name", 4),
    ];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.STRING, "'''", 8, 0),
    ]);
    _assertErrorAndTokens(ScannerErrorCode.UNTERMINATED_STRING_LITERAL, 7,
        "'''\$name", expectedTokens);
  }

  void test_string_raw_multi_double() {
    _assertToken(TokenType.STRING, "r\"\"\"line1\nline2\"\"\"");
  }

  void test_string_raw_multi_single() {
    _assertToken(TokenType.STRING, "r'''string'''");
  }

  void test_string_raw_multi_unterminated() {
    String source = "r'''string";
    List<Token> expectedTokens = [];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.STRING, "r'''string'''", 0, 10),
    ]);
    _assertErrorAndTokens(ScannerErrorCode.UNTERMINATED_STRING_LITERAL, 9,
        source, expectedTokens);
  }

  void test_string_raw_simple_double() {
    _assertToken(TokenType.STRING, "r\"string\"");
  }

  void test_string_raw_simple_single() {
    _assertToken(TokenType.STRING, "r'string'");
  }

  void test_string_raw_simple_unterminated_eof() {
    String source = "r'string";
    List<Token> expectedTokens = [];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.STRING, "r'string'", 0, 8),
    ]);
    _assertErrorAndTokens(ScannerErrorCode.UNTERMINATED_STRING_LITERAL, 7,
        source, expectedTokens);
  }

  void test_string_raw_simple_unterminated_eol() {
    String source = "r'string\n";
    List<Token> expectedTokens = [];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.STRING, "r'string'", 0, 8),
    ]);
    _assertErrorAndTokens(ScannerErrorCode.UNTERMINATED_STRING_LITERAL, 7,
        source, expectedTokens);
  }

  void test_string_simple_double() {
    _assertToken(TokenType.STRING, "\"string\"");
  }

  void test_string_simple_escapedDollar() {
    _assertToken(TokenType.STRING, "'a\\\$b'");
  }

  void test_string_simple_interpolation_adjacentIdentifiers() {
    _assertTokens("'\$a\$b'", [
      new StringToken(TokenType.STRING, "'", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 1),
      new StringToken(TokenType.IDENTIFIER, "a", 2),
      new StringToken(TokenType.STRING, "", 3),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 3),
      new StringToken(TokenType.IDENTIFIER, "b", 4),
      new StringToken(TokenType.STRING, "'", 5)
    ]);
  }

  void test_string_simple_interpolation_block() {
    _assertTokens("'Hello \${name}!'", [
      new StringToken(TokenType.STRING, "'Hello ", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_EXPRESSION, "\${", 7),
      new StringToken(TokenType.IDENTIFIER, "name", 9),
      new Token(TokenType.CLOSE_CURLY_BRACKET, 13),
      new StringToken(TokenType.STRING, "!'", 14)
    ]);
  }

  void test_string_simple_interpolation_blockWithNestedMap() {
    _assertTokens("'a \${f({'b' : 'c'})} d'", [
      new StringToken(TokenType.STRING, "'a ", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_EXPRESSION, "\${", 3),
      new StringToken(TokenType.IDENTIFIER, "f", 5),
      new Token(TokenType.OPEN_PAREN, 6),
      new Token(TokenType.OPEN_CURLY_BRACKET, 7),
      new StringToken(TokenType.STRING, "'b'", 8),
      new Token(TokenType.COLON, 12),
      new StringToken(TokenType.STRING, "'c'", 14),
      new Token(TokenType.CLOSE_CURLY_BRACKET, 17),
      new Token(TokenType.CLOSE_PAREN, 18),
      new Token(TokenType.CLOSE_CURLY_BRACKET, 19),
      new StringToken(TokenType.STRING, " d'", 20)
    ]);
  }

  void test_string_simple_interpolation_firstAndLast() {
    _assertTokens("'\$greeting \$name'", [
      new StringToken(TokenType.STRING, "'", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 1),
      new StringToken(TokenType.IDENTIFIER, "greeting", 2),
      new StringToken(TokenType.STRING, " ", 10),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 11),
      new StringToken(TokenType.IDENTIFIER, "name", 12),
      new StringToken(TokenType.STRING, "'", 16)
    ]);
  }

  void test_string_simple_interpolation_identifier() {
    _assertTokens("'Hello \$name!'", [
      new StringToken(TokenType.STRING, "'Hello ", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 7),
      new StringToken(TokenType.IDENTIFIER, "name", 8),
      new StringToken(TokenType.STRING, "!'", 12)
    ]);
  }

  void test_string_simple_interpolation_missingIdentifier() {
    var expectedTokens = <Token>[
      new StringToken(TokenType.STRING, "'", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 1),
      new StringToken(TokenType.IDENTIFIER, "x", 2),
      new StringToken(TokenType.STRING, "", 3),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 3),
    ];
    var expectedErrors = <TestError>[];
    // Fasta scanner inserts a synthetic identifier
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.IDENTIFIER, "", 4, 0),
      new StringToken(TokenType.STRING, "'", 4),
    ]);
    expectedErrors.addAll([
      new TestError(4, ScannerErrorCode.MISSING_IDENTIFIER, null),
    ]);
    ErrorListener listener = new ErrorListener();
    Token token = scanWithListener("'\$x\$'", listener);
    listener.assertErrors(expectedErrors);
    _checkTokens(token, expectedTokens);
  }

  void test_string_simple_interpolation_nonIdentifier() {
    var expectedTokens = <Token>[
      new StringToken(TokenType.STRING, "'", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 1),
    ];
    var expectedErrors = <TestError>[];
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.IDENTIFIER, "", 2),
    ]);
    expectedErrors.addAll([
      new TestError(2, ScannerErrorCode.MISSING_IDENTIFIER, null),
    ]);
    expectedTokens.addAll([
      new StringToken(TokenType.STRING, "1'", 2),
    ]);
    ErrorListener listener = new ErrorListener();
    Token token = scanWithListener("'\$1'", listener);
    listener.assertErrors(expectedErrors);
    _checkTokens(token, expectedTokens);
  }

  void test_string_simple_single() {
    _assertToken(TokenType.STRING, "'string'");
  }

  void test_string_simple_unterminated_eof() {
    String source = "'string";
    List<Token> expectedTokens = [];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.STRING, "'string'", 0, 7),
    ]);
    _assertErrorAndTokens(ScannerErrorCode.UNTERMINATED_STRING_LITERAL, 6,
        source, expectedTokens);
  }

  void test_string_simple_unterminated_eol() {
    String source = "'string\r";
    List<Token> expectedTokens = [];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.STRING, "'string'", 0, 7),
    ]);
    _assertErrorAndTokens(ScannerErrorCode.UNTERMINATED_STRING_LITERAL, 6,
        source, expectedTokens);
  }

  void test_string_simple_unterminated_interpolation_block() {
    List<Token> expectedTokens = [
      new StringToken(TokenType.STRING, "'", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_EXPRESSION, "\${", 1),
      new StringToken(TokenType.IDENTIFIER, "name", 3),
    ];
    List<TestError> expectedErrors = [
      new TestError(6, ScannerErrorCode.UNTERMINATED_STRING_LITERAL, null),
    ];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticToken(TokenType.CLOSE_CURLY_BRACKET, 7),
      new SyntheticStringToken(TokenType.STRING, "'", 7, 0),
    ]);
    expectedErrors.addAll([
      new TestError(7, ScannerErrorCode.EXPECTED_TOKEN, ['}']),
    ]);
    ErrorListener listener = new ErrorListener();
    Token token = scanWithListener("'\${name", listener);
    listener.assertErrors(expectedErrors);
    _checkTokens(token, expectedTokens);
  }

  void test_string_simple_unterminated_interpolation_identifier() {
    List<Token> expectedTokens = [
      new StringToken(TokenType.STRING, "'", 0),
      new StringToken(TokenType.STRING_INTERPOLATION_IDENTIFIER, "\$", 1),
      new StringToken(TokenType.IDENTIFIER, "name", 2),
    ];
    // Fasta inserts synthetic closers.
    expectedTokens.addAll([
      new SyntheticStringToken(TokenType.STRING, "'", 6, 0),
    ]);
    _assertErrorAndTokens(ScannerErrorCode.UNTERMINATED_STRING_LITERAL, 5,
        "'\$name", expectedTokens);
  }

  void test_sync_star() {
    Token token = _scan("sync*");
    expect(token.type.isKeyword, true);
    expect(token.lexeme, 'sync');
    expect(token.next!.type, TokenType.STAR);
    expect(token.next!.next!.type, TokenType.EOF);
  }

  void test_tilde() {
    _assertToken(TokenType.TILDE, "~");
  }

  void test_tilde_slash() {
    _assertToken(TokenType.TILDE_SLASH, "~/");
  }

  void test_tilde_slash_eq() {
    _assertToken(TokenType.TILDE_SLASH_EQ, "~/=");
  }

  void test_unclosedPairInInterpolation() {
    ErrorListener listener = new ErrorListener();
    scanWithListener("'\${(}'", listener);
  }

  void test_unmatched_openers() {
    BeginToken openBrace = _scan('{[(') as BeginToken;
    BeginToken openBracket = openBrace.next as BeginToken;
    BeginToken openParen = openBracket.next as BeginToken;
    expect(openParen.next!.type, TokenType.EOF);
    expect(openBrace.endToken, isNull);
    expect(openBracket.endToken, isNull);
    expect(openParen.endToken, isNull);
  }

  void _assertComment(TokenType commentType, String source) {
    //
    // Test without a trailing end-of-line marker
    //
    Token token = _scan(source);
    expect(token, isNotNull);
    expect(token.type, TokenType.EOF);
    Token? comment = token.precedingComments;
    expect(comment, isNotNull);
    expect(comment!.type, commentType);
    expect(comment.offset, 0);
    expect(comment.length, source.length);
    expect(comment.lexeme, source);
    //
    // Test with a trailing end-of-line marker
    //
    token = _scan("$source\n");
    expect(token, isNotNull);
    expect(token.type, TokenType.EOF);
    comment = token.precedingComments;
    expect(comment, isNotNull);
    expect(comment!.type, commentType);
    expect(comment.offset, 0);
    expect(comment.length, source.length);
    expect(comment.lexeme, source);
  }

  /**
   * Assert that scanning the given [source] produces an error with the given
   * code.
   *
   * [expectedError] the error that should be produced
   * [expectedOffset] the string offset that should be associated with the error
   * [source] the source to be scanned to produce the error
   */
  Token _assertError(
      ScannerErrorCode expectedError, int expectedOffset, String source,
      [List<Object>? arguments]) {
    ErrorListener listener = new ErrorListener();
    var tokens = scanWithListener(source, listener);
    listener.assertErrors(
        [new TestError(expectedOffset, expectedError, arguments)]);
    return tokens;
  }

  /**
   * Assert that scanning the given [source] produces an error with the given
   * code, and also produces the given tokens.
   *
   * [expectedError] the error that should be produced
   * [expectedOffset] the string offset that should be associated with the error
   * [source] the source to be scanned to produce the error
   * [expectedTokens] the tokens that are expected to be in the source
   */
  void _assertErrorAndTokens(ScannerErrorCode expectedError, int expectedOffset,
      String source, List<Token> expectedTokens) {
    ErrorListener listener = new ErrorListener();
    Token token = scanWithListener(source, listener);
    listener.assertErrors([new TestError(expectedOffset, expectedError, null)]);
    _checkTokens(token, expectedTokens);
  }

  /**
   * Assert that when scanned the given [source] contains a single keyword token
   * with the same lexeme as the original source.
   */
  void _assertKeywordToken(String source,
      {ScannerConfiguration? configuration}) {
    Token token = _scan(source, configuration: configuration);
    expect(token, isNotNull);
    expect(token.type.isKeyword, true);
    expect(token.offset, 0);
    expect(token.length, source.length);
    expect(token.lexeme, source);
    Object value = token.value();
    expect(value is Keyword, isTrue);
    expect((value as Keyword).lexeme, source);
    token = _scan(" $source ", configuration: configuration);
    expect(token, isNotNull);
    expect(token.type.isKeyword, true);
    expect(token.offset, 1);
    expect(token.length, source.length);
    expect(token.lexeme, source);
    value = token.value();
    expect(value is Keyword, isTrue);
    expect((value as Keyword).lexeme, source);
    expect(token.next!.type, TokenType.EOF);
  }

  /**
   * Assert that the token scanned from the given [source] has the
   * [expectedType].
   */
  Token _assertToken(TokenType expectedType, String source) {
    // Fasta generates errors for unmatched '{', '[', etc
    Token originalToken = _scan(source, ignoreErrors: true);
    expect(originalToken, isNotNull);
    expect(originalToken.type, expectedType);
    expect(originalToken.offset, 0);
    expect(originalToken.length, source.length);
    expect(originalToken.lexeme, source);
    if (expectedType == TokenType.SCRIPT_TAG) {
      // Adding space before the script tag is not allowed, and adding text at
      // the end changes nothing.
      return originalToken;
    } else if (expectedType == TokenType.SINGLE_LINE_COMMENT) {
      // Adding space to an end-of-line comment changes the comment.
      Token tokenWithSpaces = _scan(" $source", ignoreErrors: true);
      expect(tokenWithSpaces, isNotNull);
      expect(tokenWithSpaces.type, expectedType);
      expect(tokenWithSpaces.offset, 1);
      expect(tokenWithSpaces.length, source.length);
      expect(tokenWithSpaces.lexeme, source);
      return originalToken;
    } else if (expectedType == TokenType.INT ||
        expectedType == TokenType.INT_WITH_SEPARATORS ||
        expectedType == TokenType.DOUBLE ||
        expectedType == TokenType.DOUBLE_WITH_SEPARATORS) {
      Token tokenWithLowerD = _scan("${source}d", ignoreErrors: true);
      expect(tokenWithLowerD, isNotNull);
      expect(tokenWithLowerD.type, expectedType);
      expect(tokenWithLowerD.offset, 0);
      expect(tokenWithLowerD.length, source.length);
      expect(tokenWithLowerD.lexeme, source);
      Token tokenWithUpperD = _scan("${source}D", ignoreErrors: true);
      expect(tokenWithUpperD, isNotNull);
      expect(tokenWithUpperD.type, expectedType);
      expect(tokenWithUpperD.offset, 0);
      expect(tokenWithUpperD.length, source.length);
      expect(tokenWithUpperD.lexeme, source);
    }
    Token tokenWithSpaces = _scan(" $source ", ignoreErrors: true);
    expect(tokenWithSpaces, isNotNull);
    expect(tokenWithSpaces.type, expectedType);
    expect(tokenWithSpaces.offset, 1);
    expect(tokenWithSpaces.length, source.length);
    expect(tokenWithSpaces.lexeme, source);

    // Fasta inserts missing closers (']', '}', ')')
    //expect(originalToken.next.type, TokenType.EOF);
    return originalToken;
  }

  /**
   * Assert that when scanned the given [source] contains a sequence of tokens
   * identical to the given list of [expectedTokens].
   */
  void _assertTokens(String source, List<Token> expectedTokens) {
    Token token = _scan(source);
    _checkTokens(token, expectedTokens);
  }

  void _checkTokens(Token firstToken, List<Token> expectedTokens) {
    expect(firstToken, isNotNull);
    Token? token = firstToken;
    for (int i = 0; i < expectedTokens.length; i++) {
      Token expectedToken = expectedTokens[i];
      expect(token!.type, expectedToken.type,
          reason: "Wrong type for token $i");
      expect(token.offset, expectedToken.offset,
          reason: "Wrong offset for token $i");
      expect(token.length, expectedToken.length,
          reason: "Wrong length for token $i");
      expect(token.lexeme, expectedToken.lexeme,
          reason: "Wrong lexeme for token $i");
      token = token.next;
      expect(token, isNotNull);
    }
    expect(token!.type, TokenType.EOF);
  }

  Token _scan(String source,
      {ScannerConfiguration? configuration, bool ignoreErrors = false}) {
    ErrorListener listener = new ErrorListener();
    Token token =
        scanWithListener(source, listener, configuration: configuration);
    if (!ignoreErrors) {
      listener.assertNoErrors();
    }
    return token;
  }
}

// TODO(ahe): Remove this when http://dartbug.com/11617 is fixed.
int combineHash(int hash, int value) {
  hash = 0x1fffffff & (hash + value);
  hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
  return hash ^ (hash >> 6);
}

// TODO(ahe): Remove this when http://dartbug.com/11617 is fixed.
int finishHash(int hash) {
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash = hash ^ (hash >> 11);
  return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
}

class TestError {
  final int offset;
  final DiagnosticCode diagnosticCode;
  final List<Object>? arguments;

  TestError(this.offset, this.diagnosticCode, this.arguments);

  @override
  int get hashCode {
    int h = combineHash(combineHash(0, offset), diagnosticCode.hashCode);
    if (arguments != null) {
      for (Object argument in arguments!) {
        h = combineHash(h, argument.hashCode);
      }
    }
    return finishHash(h);
  }

  @override
  bool operator ==(Object other) {
    if (other is TestError &&
        offset == other.offset &&
        diagnosticCode == other.diagnosticCode) {
      if (arguments == null) return other.arguments == null;
      if (other.arguments == null) return false;
      if (arguments!.length != other.arguments!.length) return false;
      for (int i = 0; i < arguments!.length; i++) {
        if (arguments![i] != other.arguments![i]) return false;
      }
      return true;
    }
    return false;
  }

  @override
  String toString() {
    var argString = arguments == null ? '' : '(${arguments!.join(', ')})';
    return 'Error($offset, $diagnosticCode$argString)';
  }
}

@reflectiveTest
class TokenTypeTest {
  void test_isOperator() {
    expect(TokenType.AMPERSAND.isOperator, isTrue);
    expect(TokenType.AMPERSAND_AMPERSAND.isOperator, isTrue);
    expect(TokenType.AMPERSAND_EQ.isOperator, isTrue);
    expect(TokenType.BANG.isOperator, isTrue);
    expect(TokenType.BANG_EQ.isOperator, isTrue);
    expect(TokenType.BAR.isOperator, isTrue);
    expect(TokenType.BAR_BAR.isOperator, isTrue);
    expect(TokenType.BAR_EQ.isOperator, isTrue);
    expect(TokenType.CARET.isOperator, isTrue);
    expect(TokenType.CARET_EQ.isOperator, isTrue);
    expect(TokenType.EQ.isOperator, isTrue);
    expect(TokenType.EQ_EQ.isOperator, isTrue);
    expect(TokenType.GT.isOperator, isTrue);
    expect(TokenType.GT_EQ.isOperator, isTrue);
    expect(TokenType.GT_GT.isOperator, isTrue);
    expect(TokenType.GT_GT_EQ.isOperator, isTrue);
    expect(TokenType.INDEX.isOperator, isTrue);
    expect(TokenType.INDEX_EQ.isOperator, isTrue);
    expect(TokenType.LT.isOperator, isTrue);
    expect(TokenType.LT_EQ.isOperator, isTrue);
    expect(TokenType.LT_LT.isOperator, isTrue);
    expect(TokenType.LT_LT_EQ.isOperator, isTrue);
    expect(TokenType.MINUS.isOperator, isTrue);
    expect(TokenType.MINUS_EQ.isOperator, isTrue);
    expect(TokenType.MINUS_MINUS.isOperator, isTrue);
    expect(TokenType.PERCENT.isOperator, isTrue);
    expect(TokenType.PERCENT_EQ.isOperator, isTrue);
    expect(TokenType.PERIOD_PERIOD.isOperator, isTrue);
    expect(TokenType.PLUS.isOperator, isTrue);
    expect(TokenType.PLUS_EQ.isOperator, isTrue);
    expect(TokenType.PLUS_PLUS.isOperator, isTrue);
    expect(TokenType.QUESTION.isOperator, isTrue);
    expect(TokenType.SLASH.isOperator, isTrue);
    expect(TokenType.SLASH_EQ.isOperator, isTrue);
    expect(TokenType.STAR.isOperator, isTrue);
    expect(TokenType.STAR_EQ.isOperator, isTrue);
    expect(TokenType.TILDE.isOperator, isTrue);
    expect(TokenType.TILDE_SLASH.isOperator, isTrue);
    expect(TokenType.TILDE_SLASH_EQ.isOperator, isTrue);
  }

  void test_isUserDefinableOperator() {
    expect(TokenType.AMPERSAND.isUserDefinableOperator, isTrue);
    expect(TokenType.BAR.isUserDefinableOperator, isTrue);
    expect(TokenType.CARET.isUserDefinableOperator, isTrue);
    expect(TokenType.EQ_EQ.isUserDefinableOperator, isTrue);
    expect(TokenType.GT.isUserDefinableOperator, isTrue);
    expect(TokenType.GT_EQ.isUserDefinableOperator, isTrue);
    expect(TokenType.GT_GT.isUserDefinableOperator, isTrue);
    expect(TokenType.INDEX.isUserDefinableOperator, isTrue);
    expect(TokenType.INDEX_EQ.isUserDefinableOperator, isTrue);
    expect(TokenType.LT.isUserDefinableOperator, isTrue);
    expect(TokenType.LT_EQ.isUserDefinableOperator, isTrue);
    expect(TokenType.LT_LT.isUserDefinableOperator, isTrue);
    expect(TokenType.MINUS.isUserDefinableOperator, isTrue);
    expect(TokenType.PERCENT.isUserDefinableOperator, isTrue);
    expect(TokenType.PLUS.isUserDefinableOperator, isTrue);
    expect(TokenType.SLASH.isUserDefinableOperator, isTrue);
    expect(TokenType.STAR.isUserDefinableOperator, isTrue);
    expect(TokenType.TILDE.isUserDefinableOperator, isTrue);
    expect(TokenType.TILDE_SLASH.isUserDefinableOperator, isTrue);
  }
}
