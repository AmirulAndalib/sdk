// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:core' as type;
import 'dart:core';

import 'package:_fe_analyzer_shared/src/parser/stack_listener.dart'
    show NullValues;
import 'package:_fe_analyzer_shared/src/parser/stack_listener.dart' as type;
import 'package:_fe_analyzer_shared/src/scanner/scanner.dart' as type
    show Token;
import 'package:_fe_analyzer_shared/src/type_inference/assigned_variables.dart'
    as type;
import 'package:_fe_analyzer_shared/src/util/value_kind.dart';
import 'package:kernel/ast.dart' as type;

import '../base/combinator.dart' as type;
import '../base/configuration.dart' as type;
import '../base/constant_context.dart' as type;
import '../base/identifiers.dart' as type;
import '../base/modifiers.dart' as type;
import '../base/operator.dart' as type;
import '../builder/constructor_reference_builder.dart' as type;
import '../builder/declaration_builders.dart' as type;
import '../builder/formal_parameter_builder.dart' as type;
import '../builder/metadata_builder.dart' as type;
import '../builder/record_type_builder.dart' as type;
import '../builder/type_builder.dart' as type;
import '../fragment/fragment.dart' as type;
import '../kernel/body_builder.dart' as type
    show
        Condition,
        ExpressionOrPatternGuardCase,
        FormalParameters,
        JumpTarget,
        Label;
import '../kernel/expression_generator.dart' as type;
import 'outline_builder.dart' as type;

class ValueKinds {
  static const ValueKind AnnotationList =
      const SingleValueKind<List<type.Expression>>();
  static const ValueKind AnnotationListOrNull =
      const SingleValueKind<List<type.Expression>>(NullValues.Metadata);
  static const ValueKind Arguments = const SingleValueKind<type.Arguments>();
  static const ValueKind ArgumentsOrNull =
      const SingleValueKind<type.Arguments>(NullValues.Arguments);
  static const ValueKind ArgumentsTokenOrNull =
      const SingleValueKind<type.Token>(NullValues.Arguments);
  static const ValueKind AssignedVariablesNodeInfo =
      const SingleValueKind<type.AssignedVariablesNodeInfo>();
  static const ValueKind AsyncMarker =
      const SingleValueKind<type.AsyncMarker>();
  static const ValueKind AsyncModifier =
      const SingleValueKind<type.AsyncMarker>();
  static const ValueKind AwaitTokenOrNull =
      const SingleValueKind<type.Token>(NullValues.AwaitToken);
  static const ValueKind BreakTarget =
      const SingleValueKind<type.JumpTarget>(NullValues.BreakTarget);
  static const ValueKind Bool = const SingleValueKind<bool>();
  static const ValueKind CombinatorListOrNull =
      const SingleValueKind<List<type.CombinatorBuilder>>(
          NullValues.Combinators);
  static const ValueKind Condition = const SingleValueKind<type.Condition>();
  static const ValueKind ConfigurationListOrNull =
      const SingleValueKind<List<type.Configuration>>(
          NullValues.ConditionalUris);
  static const ValueKind ConstantContext =
      const SingleValueKind<type.ConstantContext>();
  static const ValueKind ConstructorReferenceBuilderOrNull =
      const SingleValueKind<type.ConstructorReferenceBuilder>(
          NullValues.ConstructorReference);
  static const ValueKind ContinueTarget =
      const SingleValueKind<type.JumpTarget>(NullValues.ContinueTarget);
  static const ValueKind DartType = const SingleValueKind<type.DartType>();
  static const ValueKind EnumConstantInfo =
      const SingleValueKind<type.EnumConstantInfo>();
  static const ValueKind EnumConstantInfoOrNull =
      const SingleValueKind<type.EnumConstantInfo>(NullValues.EnumConstantInfo);
  static const ValueKind EnumConstantInfoOrParserRecovery =
      const UnionValueKind([EnumConstantInfo, ParserRecovery]);
  static const ValueKind Expression = const SingleValueKind<type.Expression>();
  static const ValueKind ExpressionOrPatternGuardCase =
      const SingleValueKind<type.ExpressionOrPatternGuardCase>();
  static const ValueKind ExpressionOrPatternGuardCaseList =
      const SingleValueKind<List<type.ExpressionOrPatternGuardCase>>();
  static const ValueKind ExpressionOrNull =
      const SingleValueKind<type.Expression>(NullValues.Expression);
  static const ValueKind FieldInitializerTokenOrNull =
      const SingleValueKind<type.Token>(NullValues.FieldInitializer);
  static const ValueKind FieldInitializerOrNull =
      const SingleValueKind<type.Expression>(NullValues.FieldInitializer);
  static const ValueKind FormalParameters =
      const SingleValueKind<type.FormalParameters>();
  static const ValueKind FormalList =
      const SingleValueKind<List<type.FormalParameterBuilder>>();
  static const ValueKind FormalListOrNull =
      const SingleValueKind<List<type.FormalParameterBuilder>>(
          NullValues.FormalParameters);
  static const ValueKind FormalParameterBuilder =
      const SingleValueKind<type.FormalParameterBuilder>();
  static const ValueKind FunctionTypeParameterBuilder =
      const SingleValueKind<type.FunctionTypeParameterBuilder>();
  static const ValueKind FunctionTypeParameterBuilderList =
      const SingleValueKind<List<type.FunctionTypeParameterBuilder>>();
  static const ValueKind Generator = const SingleValueKind<type.Generator>();
  static const ValueKind Identifier = const SingleValueKind<type.Identifier>();
  static const ValueKind IdentifierOrNull =
      const SingleValueKind<type.Identifier>(NullValues.Identifier);
  static const ValueKind IdentifierOrParserRecovery =
      const UnionValueKind([Identifier, ParserRecovery]);
  static const ValueKind IdentifierOrParserRecoveryOrNull =
      const UnionValueKind([IdentifierOrNull, ParserRecovery]);
  static const ValueKind IdentifierOrOperatorOrParserRecovery =
      const UnionValueKind([Identifier, Operator, ParserRecovery]);
  static const ValueKind Initializer =
      const SingleValueKind<type.Initializer>();
  static const ValueKind Integer = const SingleValueKind<int>();
  static const ValueKind Label = const SingleValueKind<type.Label>();
  static const ValueKind LabelListOrNull =
      const SingleValueKind<List<type.Label>>(NullValues.Labels);
  static const ValueKind MapLiteralEntry =
      const SingleValueKind<type.MapLiteralEntry>();
  static const ValueKind MapPatternEntry =
      const SingleValueKind<type.MapPatternEntry>();
  static const ValueKind Pattern = const SingleValueKind<type.Pattern>();
  static const ValueKind PatternGuard =
      const SingleValueKind<type.PatternGuard>();
  static const ValueKind PatternOrNull =
      const SingleValueKind<type.Pattern>(NullValues.Pattern);
  static const ValueKind PatternListOrNull =
      const SingleValueKind<List<type.Pattern>>(NullValues.PatternList);
  static const ValueKind PrefixOrNull =
      const SingleValueKind<type.Identifier>(NullValues.Prefix);
  static const ValueKind PrefixOrParserRecoveryOrNull =
      const UnionValueKind([PrefixOrNull, ParserRecovery]);
  static const ValueKind MethodBody = const SingleValueKind<type.MethodBody>();
  static const ValueKind Modifiers = const SingleValueKind<type.Modifiers>();
  static const ValueKind Name = const SingleValueKind<type.String>();
  static const ValueKind NamedExpression =
      const SingleValueKind<type.NamedExpression>();
  static const ValueKind NameList = const SingleValueKind<List<type.String>>();
  static const ValueKind NameListOrNull =
      const SingleValueKind<List<type.String>>(NullValues.IdentifierList);
  static const ValueKind NameListOrParserRecovery =
      const UnionValueKind([NameList, ParserRecovery]);
  static const ValueKind NameOrNull =
      const SingleValueKind<type.String>(NullValues.Name);
  static const ValueKind NameOrOperator =
      const UnionValueKind([Name, Operator]);
  static const ValueKind NameOrParserRecovery =
      const UnionValueKind([Name, ParserRecovery]);
  static const ValueKind NameOrParserRecoveryOrNull =
      const UnionValueKind([NameOrNull, ParserRecovery]);
  static const ValueKind MetadataListOrNull =
      const SingleValueKind<List<type.MetadataBuilder>>(NullValues.Metadata);
  static const ValueKind ObjectList = const SingleValueKind<List<Object>>();
  static const ValueKind Operator = const SingleValueKind<type.Operator>();
  static const ValueKind OperatorListOrNull =
      const SingleValueKind<List<type.Operator>>(NullValues.OperatorList);
  static const ValueKind ParserRecovery =
      const SingleValueKind<type.ParserRecovery>();
  static const ValueKind QualifiedName =
      const SingleValueKind<type.QualifiedName>();
  static const ValueKind RecordTypeFieldBuilder =
      const SingleValueKind<type.RecordTypeFieldBuilder>();
  static const ValueKind RecordTypeFieldBuilderListOrNull =
      const SingleValueKind<List<type.RecordTypeFieldBuilder>>(
          NullValues.RecordTypeFieldList);
  static const ValueKind Selector = const SingleValueKind<type.Selector>();
  static const ValueKind SwitchCase = const SingleValueKind<type.SwitchCase>();
  static const ValueKind SwitchCaseList =
      const SingleValueKind<List<type.SwitchCase>>();
  static const ValueKind SwitchExpressionCase =
      const SingleValueKind<type.SwitchExpressionCase>();
  static const ValueKind SwitchExpressionCaseList =
      const SingleValueKind<List<type.SwitchExpressionCase>>();
  static const ValueKind Statement = const SingleValueKind<type.Statement>();
  static const ValueKind StatementOrNull =
      const SingleValueKind<type.Statement>(NullValues.Block);
  static const ValueKind StatementListOrNullList =
      const SingleValueKind<List<List<type.Statement>?>>();
  static const ValueKind String = const SingleValueKind<type.String>();
  static const ValueKind Token = const SingleValueKind<type.Token>();
  static const ValueKind TokenOrNull =
      const SingleValueKind<type.Token>(NullValues.Token);
  static const ValueKind TokenOrParserRecovery =
      const UnionValueKind([Token, ParserRecovery]);
  static const ValueKind TypeOrNull =
      const SingleValueKind<type.TypeBuilder>(NullValues.TypeBuilder);
  static const ValueKind TypeArguments =
      const SingleValueKind<List<type.TypeBuilder>>();
  static const ValueKind TypeArgumentsOrNull =
      const SingleValueKind<List<type.TypeBuilder>>(NullValues.TypeArguments);
  static const ValueKind TypeBuilder =
      const SingleValueKind<type.TypeBuilder>();
  static const ValueKind TypeBuilderOrNull =
      const SingleValueKind<type.TypeBuilder>(NullValues.TypeBuilder);
  static const ValueKind TypeBuilderList =
      const SingleValueKind<List<type.TypeBuilder>>();
  static const ValueKind TypeBuilderListOrNull =
      const SingleValueKind<List<type.TypeBuilder>>(NullValues.TypeBuilderList);
  static const ValueKind TypeParameterFragmentListOrNull =
      const SingleValueKind<List<type.TypeParameterFragment>>(
          NullValues.NominalParameters);
  static const ValueKind NominalVariableListOrNull =
      const SingleValueKind<List<type.NominalParameterBuilder>>(
          NullValues.NominalParameters);
  static const ValueKind VariableDeclarationListOrNull =
      const SingleValueKind<List<type.VariableDeclaration>>(
          NullValues.VariableDeclarationList);
}
