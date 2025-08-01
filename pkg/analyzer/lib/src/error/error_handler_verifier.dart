// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// @docImport 'dart:async';
library;

import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_provider.dart';
import 'package:analyzer/src/dart/element/type_system.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/error/return_type_verifier.dart';
import 'package:analyzer/src/generated/error_verifier.dart';
import 'package:collection/collection.dart';

/// Reports on invalid functions passed as error handlers.
///
/// Functions must either accept exactly one positional parameter, or exactly
/// two positional parameters. The one parameter (or the first parameter) must
/// have a type of `dynamic`, `Object`, or `Object?`. If a second parameter is
/// accepted, it must have a type of `StackTrace`.
///
/// A function is checked if it is passed as:
/// * as the first argument to [Future.catchError],
/// * as the 'onError' named argument to [Future.then],
/// * as the first argument to [Stream.handleError],
/// * as the 'onError' argument to [Stream.listen],
/// * as the first argument to [StreamSubscription.onError],
///
/// Additionally, a function passed as the first argument to
/// `Future<T>.catchError` must return `FutureOr<T>`, and any return statements
/// in a function literal must return a value of type `FutureOr<T>`.
class ErrorHandlerVerifier {
  final DiagnosticReporter _diagnosticReporter;

  final TypeProviderImpl _typeProvider;

  final TypeSystemImpl _typeSystem;

  final ReturnTypeVerifier _returnTypeVerifier;

  final bool _strictCasts;

  ErrorHandlerVerifier(
    this._diagnosticReporter,
    this._typeProvider,
    this._typeSystem, {
    required bool strictCasts,
  }) : _strictCasts = strictCasts,
       _returnTypeVerifier = ReturnTypeVerifier(
         typeProvider: _typeProvider,
         typeSystem: _typeSystem,
         diagnosticReporter: _diagnosticReporter,
         strictCasts: strictCasts,
       );

  void verifyMethodInvocation(MethodInvocation node) {
    var target = node.realTarget;
    if (target == null) {
      return;
    }

    if (node.argumentList.arguments.isEmpty) {
      return;
    }

    var targetType = target.staticType;
    if (targetType == null) {
      return;
    }
    var methodName = node.methodName.name;
    if (methodName == 'catchError' && targetType.isDartAsyncFuture) {
      var callback = node.argumentList.arguments.first;
      if (callback is NamedExpression) {
        // TODO(srawlins): The comment below is wrong, given
        // `named-arguments-anywhere`.
        // This implies that no positional arguments are passed.
        return;
      }
      _checkFutureCatchErrorOnError(target, callback);
      return;
    }

    if (methodName == 'then' && targetType.isDartAsyncFuture) {
      var callback = node.argumentList.arguments
          .whereType<NamedExpression>()
          .firstWhereOrNull(
            (argument) => argument.name.label.name == 'onError',
          );
      if (callback == null) {
        return;
      }
      var callbackType = callback.staticType;
      if (callbackType == null) {
        return;
      }
      if (callbackType is FunctionTypeImpl) {
        // TODO(srawlins): Also check return type of the 'onError' named
        // argument to [Future<T>.then].
        _checkErrorHandlerFunctionType(
          callback,
          callbackType,
          _typeProvider.voidType,
          checkFirstParameterType: callback.expression is FunctionExpression,
        );
        return;
      }
      // [callbackType] might be dart:core's Function, or something not
      // assignable to Function, in which case an error is reported elsewhere.
    }

    if (methodName == 'handleError' &&
        _isDartCoreAsyncType(targetType, 'Stream')) {
      var callback = node.argumentList.arguments.first;
      if (callback is NamedExpression) {
        // This implies that no positional arguments are passed.
        return;
      }
      var callbackType = callback.staticType;
      if (callbackType == null) {
        return;
      }
      if (callbackType is FunctionTypeImpl) {
        _checkErrorHandlerFunctionType(
          callback,
          callbackType,
          _typeProvider.voidType,
          checkFirstParameterType: callback is FunctionExpression,
        );
        return;
      }
      // [callbackType] might be dart:core's Function, or something not
      // assignable to Function, in which case an error is reported elsewhere.
    }

    if (methodName == 'listen' && _isDartCoreAsyncType(targetType, 'Stream')) {
      var callback = node.argumentList.arguments
          .whereType<NamedExpression>()
          .firstWhereOrNull(
            (argument) => argument.name.label.name == 'onError',
          );
      if (callback == null) {
        return;
      }
      var callbackType = callback.staticType;
      if (callbackType == null) {
        return;
      }
      if (callbackType is FunctionTypeImpl) {
        _checkErrorHandlerFunctionType(
          callback,
          callbackType,
          _typeProvider.voidType,
          checkFirstParameterType: callback.expression is FunctionExpression,
        );
        return;
      }
      // [callbackType] might be dart:core's Function, or something not
      // assignable to Function, in which case an error is reported elsewhere.
    }

    if (methodName == 'onError' &&
        _isDartCoreAsyncType(targetType, 'StreamSubscription')) {
      var callback = node.argumentList.arguments.first;
      if (callback is NamedExpression) {
        // This implies that no positional arguments are passed.
        return;
      }
      var callbackType = callback.staticType;
      if (callbackType == null) {
        return;
      }
      if (callbackType is FunctionTypeImpl) {
        _checkErrorHandlerFunctionType(
          callback,
          callbackType,
          _typeProvider.voidType,
          checkFirstParameterType: callback is FunctionExpression,
        );
        return;
      }
      // [callbackType] might be dart:core's Function, or something not
      // assignable to Function, in which case an error is reported elsewhere.
    }
  }

  /// Checks that [expression], a function with static type [expressionType], is
  /// a valid error handler.
  ///
  /// Only checks the first parameter type if [checkFirstParameterType] is true.
  /// Certain error handlers are allowed to specify a different type for their
  /// first parameter.
  void _checkErrorHandlerFunctionType(
    Expression expression,
    FunctionTypeImpl expressionType,
    DartType expectedFunctionReturnType, {
    bool checkFirstParameterType = true,
  }) {
    void report() {
      _diagnosticReporter.atNode(
        expression,
        WarningCode.ARGUMENT_TYPE_NOT_ASSIGNABLE_TO_ERROR_HANDLER,
        arguments: [expressionType, expectedFunctionReturnType],
      );
    }

    var parameters = expressionType.formalParameters;
    if (parameters.isEmpty) {
      return report();
    }
    var firstParameter = parameters.first;
    if (firstParameter.isNamed) {
      return report();
    } else if (checkFirstParameterType) {
      if (!_typeSystem.isSubtypeOf(
        _typeProvider.objectType,
        firstParameter.type,
      )) {
        return report();
      }
    }
    if (parameters.length == 2) {
      var secondParameter = parameters[1];
      if (secondParameter.isNamed) {
        return report();
      } else {
        if (!_typeSystem.isSubtypeOf(
          _typeProvider.stackTraceType,
          secondParameter.type,
        )) {
          return report();
        }
      }
    } else if (parameters.length > 2) {
      return report();
    }
  }

  /// Check the 'onError' argument given to [Future.catchError].
  void _checkFutureCatchErrorOnError(Expression target, Expression callback) {
    var targetType = target.staticType as InterfaceTypeImpl;
    var targetFutureType = targetType.typeArguments.first;
    var expectedReturnType = _typeProvider.futureOrType(targetFutureType);
    if (callback is FunctionExpressionImpl) {
      // TODO(migration): should be FunctionType, not nullable
      var callbackType = callback.staticType as FunctionTypeImpl;
      _checkErrorHandlerFunctionType(
        callback,
        callbackType,
        expectedReturnType,
      );
      var catchErrorOnErrorExecutable = EnclosingExecutableContext(
        callback.declaredFragment!.element,
        isAsynchronous: true,
        isGenerator: false,
        catchErrorOnErrorReturnType: expectedReturnType,
      );
      var returnStatementVerifier = _ReturnStatementVerifier(
        _returnTypeVerifier,
      );
      _returnTypeVerifier.enclosingExecutable = catchErrorOnErrorExecutable;
      callback.body.accept(returnStatementVerifier);
    } else {
      var callbackType = callback.staticType;
      if (callbackType is FunctionTypeImpl) {
        _checkReturnType(expectedReturnType, callbackType.returnType, callback);
        _checkErrorHandlerFunctionType(
          callback,
          callbackType,
          expectedReturnType,
        );
      } else {
        // If [callback] is not even a Function, then ErrorVerifier will have
        // reported this.
      }
    }
  }

  void _checkReturnType(
    TypeImpl expectedType,
    TypeImpl functionReturnType,
    Expression callback,
  ) {
    if (!_typeSystem.isAssignableTo(
      functionReturnType,
      expectedType,
      strictCasts: _strictCasts,
    )) {
      _diagnosticReporter.atNode(
        callback,
        WarningCode.RETURN_TYPE_INVALID_FOR_CATCH_ERROR,
        arguments: [functionReturnType, expectedType],
      );
    }
  }

  /// Returns whether [type] represents the type named [typeName], declared in
  /// the 'dart:async' library.
  bool _isDartCoreAsyncType(DartType type, String typeName) =>
      type is InterfaceType &&
      type.element.name == typeName &&
      type.element.library.isDartAsync;
}

/// Visits a function body, looking for return statements.
class _ReturnStatementVerifier extends RecursiveAstVisitor<void> {
  final ReturnTypeVerifier _returnTypeVerifier;

  _ReturnStatementVerifier(this._returnTypeVerifier);

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    _returnTypeVerifier.verifyExpressionFunctionBody(node);
    super.visitExpressionFunctionBody(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Do not visit within [node]. We have no interest in return statements
    // within.
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    _returnTypeVerifier.verifyReturnStatement(node);
    super.visitReturnStatement(node);
  }
}
