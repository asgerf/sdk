// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.parser.error_kind;

/// Kinds of error codes.
enum ErrorKind {
  AbstractNotSync,
  AsciiControlCharacter,
  AsyncAsIdentifier,
  AwaitAsIdentifier,
  AwaitForNotAsync,
  AwaitNotAsync,
  BuiltInIdentifierAsType,
  BuiltInIdentifierInDeclaration,
  EmptyNamedParameterList,
  EmptyOptionalParameterList,
  Encoding,
  ExpectedBlockToSkip,
  ExpectedBody,
  ExpectedButGot,
  ExpectedClassBody,

  /// This error code can be used to support non-compliant (with respect to
  /// Dart Language Specification) Dart VM native clauses. See
  /// [dart_vm_native.dart].
  ExpectedClassBodyToSkip,
  ExpectedDeclaration,
  ExpectedExpression,
  ExpectedFunctionBody,
  ExpectedHexDigit,
  ExpectedIdentifier,
  ExpectedOpenParens,
  ExpectedString,
  ExpectedType,
  ExtraneousModifier,
  ExtraneousModifierReplace,
  FactoryNotSync,
  GeneratorReturnsValue,
  InvalidAwaitFor,
  InvalidInlineFunctionType,
  InvalidSyncModifier,
  InvalidVoid,
  MissingExponent,
  NonAsciiIdentifier,
  NonAsciiWhitespace,
  OnlyTry,
  PositionalParameterWithEquals,
  RequiredParameterWithDefault,
  SetterNotSync,
  StackOverflow,
  UnexpectedDollarInString,
  UnexpectedToken,
  UnmatchedToken,
  UnsupportedPrefixPlus,
  UnterminatedComment,
  UnterminatedString,
  UnterminatedToken,
  YieldAsIdentifier,
  YieldNotGenerator,
  Unspecified,
}
