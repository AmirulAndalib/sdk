// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// THIS FILE IS GENERATED. DO NOT EDIT.
//
// Instead modify 'pkg/analyzer/messages.yaml' and run
// 'dart run pkg/analyzer/tool/messages/generate.dart' to update.

// While transitioning `HintCodes` to `WarningCodes`, we refer to deprecated
// codes here.
// ignore_for_file: deprecated_member_use_from_same_package
//
// Generated comments don't quite align with flutter style.
// ignore_for_file: flutter_style_todos

/// @docImport 'package:analyzer/src/dart/error/syntactic_errors.g.dart';
/// @docImport 'package:analyzer/src/error/inference_error.dart';
@Deprecated(
  // This library is deprecated to prevent it from being accidentally imported
  // It should only be imported by the corresponding non-code-generated library
  // (which suppresses the deprecation warning using an "ignore" comment).
  'Use package:analyzer/src/dart/error/ffi_code.dart instead',
)
library;

import "package:_fe_analyzer_shared/src/base/errors.dart";

class FfiCode extends DiagnosticCode {
  ///  No parameters.
  static const FfiCode ABI_SPECIFIC_INTEGER_INVALID = FfiCode(
    'ABI_SPECIFIC_INTEGER_INVALID',
    "Classes extending 'AbiSpecificInteger' must have exactly one const "
        "constructor, no other members, and no type parameters.",
    correctionMessage:
        "Try removing all type parameters, removing all members, and adding "
        "one const constructor.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode ABI_SPECIFIC_INTEGER_MAPPING_EXTRA = FfiCode(
    'ABI_SPECIFIC_INTEGER_MAPPING_EXTRA',
    "Classes extending 'AbiSpecificInteger' must have exactly one "
        "'AbiSpecificIntegerMapping' annotation specifying the mapping from "
        "ABI to a 'NativeType' integer with a fixed size.",
    correctionMessage: "Try removing the extra annotation.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode ABI_SPECIFIC_INTEGER_MAPPING_MISSING = FfiCode(
    'ABI_SPECIFIC_INTEGER_MAPPING_MISSING',
    "Classes extending 'AbiSpecificInteger' must have exactly one "
        "'AbiSpecificIntegerMapping' annotation specifying the mapping from "
        "ABI to a 'NativeType' integer with a fixed size.",
    correctionMessage: "Try adding an annotation.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the value of the invalid mapping
  static const FfiCode ABI_SPECIFIC_INTEGER_MAPPING_UNSUPPORTED = FfiCode(
    'ABI_SPECIFIC_INTEGER_MAPPING_UNSUPPORTED',
    "Invalid mapping to '{0}'; only mappings to 'Int8', 'Int16', 'Int32', "
        "'Int64', 'Uint8', 'Uint16', 'UInt32', and 'Uint64' are supported.",
    correctionMessage:
        "Try changing the value to 'Int8', 'Int16', 'Int32', 'Int64', 'Uint8', "
        "'Uint16', 'UInt32', or 'Uint64'.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode ADDRESS_POSITION = FfiCode(
    'ADDRESS_POSITION',
    "The '.address' expression can only be used as argument to a leaf native "
        "external call.",
  );

  ///  No parameters.
  static const FfiCode ADDRESS_RECEIVER = FfiCode(
    'ADDRESS_RECEIVER',
    "The receiver of '.address' must be a concrete 'TypedData', a concrete "
        "'TypedData' '[]', an 'Array', an 'Array' '[]', a Struct field, or a "
        "Union field.",
    correctionMessage:
        "Change the receiver of '.address' to one of the allowed kinds.",
  );

  ///  No parameters.
  static const FfiCode ANNOTATION_ON_POINTER_FIELD = FfiCode(
    'ANNOTATION_ON_POINTER_FIELD',
    "Fields in a struct class whose type is 'Pointer' shouldn't have any "
        "annotations.",
    correctionMessage: "Try removing the annotation.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the argument
  static const FfiCode ARGUMENT_MUST_BE_A_CONSTANT = FfiCode(
    'ARGUMENT_MUST_BE_A_CONSTANT',
    "Argument '{0}' must be a constant.",
    correctionMessage: "Try replacing the value with a literal or const.",
    hasPublishedDocs: true,
  );

  ///  No parameters
  static const FfiCode ARGUMENT_MUST_BE_NATIVE = FfiCode(
    'ARGUMENT_MUST_BE_NATIVE',
    "Argument to 'Native.addressOf' must be annotated with @Native",
    correctionMessage:
        "Try passing a static function or field annotated with '@Native'",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the struct or union class
  static const FfiCode COMPOUND_IMPLEMENTS_FINALIZABLE = FfiCode(
    'COMPOUND_IMPLEMENTS_FINALIZABLE',
    "The class '{0}' can't implement Finalizable.",
    correctionMessage: "Try removing the implements clause from '{0}'.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode CREATION_OF_STRUCT_OR_UNION = FfiCode(
    'CREATION_OF_STRUCT_OR_UNION',
    "Subclasses of 'Struct' and 'Union' are backed by native memory, and can't "
        "be instantiated by a generative constructor.",
    correctionMessage:
        "Try allocating it via allocation, or load from a 'Pointer'.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the subclass
  ///  1: the name of the superclass
  static const FfiCode EMPTY_STRUCT = FfiCode(
    'EMPTY_STRUCT',
    "The class '{0}' can't be empty because it's a subclass of '{1}'.",
    correctionMessage:
        "Try adding a field to '{0}' or use a different superclass.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode EXTRA_ANNOTATION_ON_STRUCT_FIELD = FfiCode(
    'EXTRA_ANNOTATION_ON_STRUCT_FIELD',
    "Fields in a struct class must have exactly one annotation indicating the "
        "native type.",
    correctionMessage: "Try removing the extra annotation.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode EXTRA_SIZE_ANNOTATION_CARRAY = FfiCode(
    'EXTRA_SIZE_ANNOTATION_CARRAY',
    "'Array's must have exactly one 'Array' annotation.",
    correctionMessage: "Try removing the extra annotation.",
    hasPublishedDocs: true,
  );

  ///  No parameters
  static const FfiCode FFI_NATIVE_INVALID_DUPLICATE_DEFAULT_ASSET = FfiCode(
    'FFI_NATIVE_INVALID_DUPLICATE_DEFAULT_ASSET',
    "There may be at most one @DefaultAsset annotation on a library.",
    correctionMessage: "Try removing the extra annotation.",
    hasPublishedDocs: true,
  );

  ///  No parameters
  static const FfiCode FFI_NATIVE_INVALID_MULTIPLE_ANNOTATIONS = FfiCode(
    'FFI_NATIVE_INVALID_MULTIPLE_ANNOTATIONS',
    "Native functions and fields must have exactly one `@Native` annotation.",
    correctionMessage: "Try removing the extra annotation.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode FFI_NATIVE_MUST_BE_EXTERNAL = FfiCode(
    'FFI_NATIVE_MUST_BE_EXTERNAL',
    "Native functions must be declared external.",
    correctionMessage: "Add the `external` keyword to the function.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode
  FFI_NATIVE_ONLY_CLASSES_EXTENDING_NATIVEFIELDWRAPPERCLASS1_CAN_BE_POINTER = FfiCode(
    'FFI_NATIVE_ONLY_CLASSES_EXTENDING_NATIVEFIELDWRAPPERCLASS1_CAN_BE_POINTER',
    "Only classes extending NativeFieldWrapperClass1 can be passed as Pointer.",
    correctionMessage: "Pass as Handle instead.",
  );

  ///  Parameters:
  ///  0: the expected number of parameters
  ///  1: the actual number of parameters
  static const FfiCode FFI_NATIVE_UNEXPECTED_NUMBER_OF_PARAMETERS = FfiCode(
    'FFI_NATIVE_UNEXPECTED_NUMBER_OF_PARAMETERS',
    "Unexpected number of Native annotation parameters. Expected {0} but has "
        "{1}.",
    correctionMessage: "Make sure parameters match the function annotated.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the expected number of parameters
  ///  1: the actual number of parameters
  static const FfiCode
  FFI_NATIVE_UNEXPECTED_NUMBER_OF_PARAMETERS_WITH_RECEIVER = FfiCode(
    'FFI_NATIVE_UNEXPECTED_NUMBER_OF_PARAMETERS_WITH_RECEIVER',
    "Unexpected number of Native annotation parameters. Expected {0} but has "
        "{1}. Native instance method annotation must have receiver as first "
        "argument.",
    correctionMessage:
        "Make sure parameters match the function annotated, including an extra "
        "first parameter for the receiver.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode FIELD_MUST_BE_EXTERNAL_IN_STRUCT = FfiCode(
    'FIELD_MUST_BE_EXTERNAL_IN_STRUCT',
    "Fields of 'Struct' and 'Union' subclasses must be marked external.",
    correctionMessage: "Try adding the 'external' modifier.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the struct class
  static const FfiCode GENERIC_STRUCT_SUBCLASS = FfiCode(
    'GENERIC_STRUCT_SUBCLASS',
    "The class '{0}' can't extend 'Struct' or 'Union' because '{0}' is "
        "generic.",
    correctionMessage: "Try removing the type parameters from '{0}'.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the method
  static const FfiCode INVALID_EXCEPTION_VALUE = FfiCode(
    'INVALID_EXCEPTION_VALUE',
    "The method {0} can't have an exceptional return value (the second "
        "argument) when the return type of the function is either 'void', "
        "'Handle' or 'Pointer'.",
    correctionMessage: "Try removing the exceptional return value.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the type of the field
  static const FfiCode INVALID_FIELD_TYPE_IN_STRUCT = FfiCode(
    'INVALID_FIELD_TYPE_IN_STRUCT',
    "Fields in struct classes can't have the type '{0}'. They can only be "
        "declared as 'int', 'double', 'Array', 'Pointer', or subtype of "
        "'Struct' or 'Union'.",
    correctionMessage:
        "Try using 'int', 'double', 'Array', 'Pointer', or subtype of 'Struct' "
        "or 'Union'.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode LEAF_CALL_MUST_NOT_RETURN_HANDLE = FfiCode(
    'LEAF_CALL_MUST_NOT_RETURN_HANDLE',
    "FFI leaf call can't return a 'Handle'.",
    correctionMessage: "Try changing the return type to primitive or struct.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode LEAF_CALL_MUST_NOT_TAKE_HANDLE = FfiCode(
    'LEAF_CALL_MUST_NOT_TAKE_HANDLE',
    "FFI leaf call can't take arguments of type 'Handle'.",
    correctionMessage: "Try changing the argument type to primitive or struct.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode MISMATCHED_ANNOTATION_ON_STRUCT_FIELD = FfiCode(
    'MISMATCHED_ANNOTATION_ON_STRUCT_FIELD',
    "The annotation doesn't match the declared type of the field.",
    correctionMessage:
        "Try using a different annotation or changing the declared type to "
        "match.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the type that is missing a native type annotation
  ///  1: the superclass which is extended by this field's class
  static const FfiCode MISSING_ANNOTATION_ON_STRUCT_FIELD = FfiCode(
    'MISSING_ANNOTATION_ON_STRUCT_FIELD',
    "Fields of type '{0}' in a subclass of '{1}' must have an annotation "
        "indicating the native type.",
    correctionMessage: "Try adding an annotation.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the method
  static const FfiCode MISSING_EXCEPTION_VALUE = FfiCode(
    'MISSING_EXCEPTION_VALUE',
    "The method {0} must have an exceptional return value (the second "
        "argument) when the return type of the function is neither 'void', "
        "'Handle', nor 'Pointer'.",
    correctionMessage: "Try adding an exceptional return value.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode MISSING_FIELD_TYPE_IN_STRUCT = FfiCode(
    'MISSING_FIELD_TYPE_IN_STRUCT',
    "Fields in struct classes must have an explicitly declared type of 'int', "
        "'double' or 'Pointer'.",
    correctionMessage: "Try using 'int', 'double' or 'Pointer'.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode MISSING_SIZE_ANNOTATION_CARRAY = FfiCode(
    'MISSING_SIZE_ANNOTATION_CARRAY',
    "Fields of type 'Array' must have exactly one 'Array' annotation.",
    correctionMessage:
        "Try adding an 'Array' annotation, or removing all but one of the "
        "annotations.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the type that should be a valid dart:ffi native type.
  ///  1: the name of the function whose invocation depends on this relationship
  static const FfiCode MUST_BE_A_NATIVE_FUNCTION_TYPE = FfiCode(
    'MUST_BE_A_NATIVE_FUNCTION_TYPE',
    "The type '{0}' given to '{1}' must be a valid 'dart:ffi' native function "
        "type.",
    correctionMessage:
        "Try changing the type to only use members for 'dart:ffi'.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the type that should be a subtype
  ///  1: the supertype that the subtype is compared to
  ///  2: the name of the function whose invocation depends on this relationship
  static const FfiCode MUST_BE_A_SUBTYPE = FfiCode(
    'MUST_BE_A_SUBTYPE',
    "The type '{0}' must be a subtype of '{1}' for '{2}'.",
    correctionMessage: "Try changing one or both of the type arguments.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the return type that should be 'void'.
  static const FfiCode MUST_RETURN_VOID = FfiCode(
    'MUST_RETURN_VOID',
    "The return type of the function passed to 'NativeCallable.listener' must "
        "be 'void' rather than '{0}'.",
    correctionMessage: "Try changing the return type to 'void'.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: The invalid type.
  static const FfiCode NATIVE_FIELD_INVALID_TYPE = FfiCode(
    'NATIVE_FIELD_INVALID_TYPE',
    "'{0}' is an unsupported type for native fields. Native fields only "
        "support pointers, arrays or numeric and compound types.",
    correctionMessage:
        "Try changing the type in the `@Native` annotation to a numeric FFI "
        "type, a pointer, array, or a compound class.",
    hasPublishedDocs: true,
  );

  ///  No parameters
  static const FfiCode NATIVE_FIELD_MISSING_TYPE = FfiCode(
    'NATIVE_FIELD_MISSING_TYPE',
    "The native type of this field could not be inferred and must be specified "
        "in the annotation.",
    correctionMessage:
        "Try adding a type parameter extending `NativeType` to the `@Native` "
        "annotation.",
    hasPublishedDocs: true,
  );

  ///  No parameters
  static const FfiCode NATIVE_FIELD_NOT_STATIC = FfiCode(
    'NATIVE_FIELD_NOT_STATIC',
    "Native fields must be static.",
    correctionMessage: "Try adding the modifier 'static' to this field.",
    hasPublishedDocs: true,
  );

  ///  No parameters
  static const FfiCode NATIVE_FUNCTION_MISSING_TYPE = FfiCode(
    'NATIVE_FUNCTION_MISSING_TYPE',
    "The native type of this function couldn't be inferred so it must be "
        "specified in the annotation.",
    correctionMessage:
        "Try adding a type parameter extending `NativeType` to the `@Native` "
        "annotation.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode NEGATIVE_VARIABLE_DIMENSION = FfiCode(
    'NEGATIVE_VARIABLE_DIMENSION',
    "The variable dimension of a variable-length array must be non-negative.",
    correctionMessage: "Try using a value that is zero or greater.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the function, method, or constructor having type arguments
  static const FfiCode NON_CONSTANT_TYPE_ARGUMENT = FfiCode(
    'NON_CONSTANT_TYPE_ARGUMENT',
    "The type arguments to '{0}' must be known at compile time, so they can't "
        "be type parameters.",
    correctionMessage: "Try changing the type argument to be a constant type.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the type that should be a valid dart:ffi native type.
  static const FfiCode NON_NATIVE_FUNCTION_TYPE_ARGUMENT_TO_POINTER = FfiCode(
    'NON_NATIVE_FUNCTION_TYPE_ARGUMENT_TO_POINTER',
    "Can't invoke 'asFunction' because the function signature '{0}' for the "
        "pointer isn't a valid C function signature.",
    correctionMessage:
        "Try changing the function argument in 'NativeFunction' to only use "
        "NativeTypes.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode NON_POSITIVE_ARRAY_DIMENSION = FfiCode(
    'NON_POSITIVE_ARRAY_DIMENSION',
    "Array dimensions must be positive numbers.",
    correctionMessage: "Try changing the input to a positive number.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the field
  ///  1: the type of the field
  static const FfiCode NON_SIZED_TYPE_ARGUMENT = FfiCode(
    'NON_SIZED_TYPE_ARGUMENT',
    "The type '{1}' isn't a valid type argument for '{0}'. The type argument "
        "must be a native integer, 'Float', 'Double', 'Pointer', or subtype of "
        "'Struct', 'Union', or 'AbiSpecificInteger'.",
    correctionMessage:
        "Try using a native integer, 'Float', 'Double', 'Pointer', or subtype "
        "of 'Struct', 'Union', or 'AbiSpecificInteger'.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode PACKED_ANNOTATION = FfiCode(
    'PACKED_ANNOTATION',
    "Structs must have at most one 'Packed' annotation.",
    correctionMessage: "Try removing extra 'Packed' annotations.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode PACKED_ANNOTATION_ALIGNMENT = FfiCode(
    'PACKED_ANNOTATION_ALIGNMENT',
    "Only packing to 1, 2, 4, 8, and 16 bytes is supported.",
    correctionMessage:
        "Try changing the 'Packed' annotation alignment to 1, 2, 4, 8, or 16.",
    hasPublishedDocs: true,
  );

  ///  No parameters.
  static const FfiCode SIZE_ANNOTATION_DIMENSIONS = FfiCode(
    'SIZE_ANNOTATION_DIMENSIONS',
    "'Array's must have an 'Array' annotation that matches the dimensions.",
    correctionMessage: "Try adjusting the arguments in the 'Array' annotation.",
    hasPublishedDocs: true,
  );

  ///  Parameters:
  ///  0: the name of the subclass
  ///  1: the name of the class being extended, implemented, or mixed in
  static const FfiCode SUBTYPE_OF_STRUCT_CLASS_IN_EXTENDS = FfiCode(
    'SUBTYPE_OF_STRUCT_CLASS',
    "The class '{0}' can't extend '{1}' because '{1}' is a subtype of "
        "'Struct', 'Union', or 'AbiSpecificInteger'.",
    correctionMessage:
        "Try extending 'Struct', 'Union', or 'AbiSpecificInteger' directly.",
    hasPublishedDocs: true,
    uniqueName: 'SUBTYPE_OF_STRUCT_CLASS_IN_EXTENDS',
  );

  ///  Parameters:
  ///  0: the name of the subclass
  ///  1: the name of the class being extended, implemented, or mixed in
  static const FfiCode SUBTYPE_OF_STRUCT_CLASS_IN_IMPLEMENTS = FfiCode(
    'SUBTYPE_OF_STRUCT_CLASS',
    "The class '{0}' can't implement '{1}' because '{1}' is a subtype of "
        "'Struct', 'Union', or 'AbiSpecificInteger'.",
    correctionMessage:
        "Try extending 'Struct', 'Union', or 'AbiSpecificInteger' directly.",
    hasPublishedDocs: true,
    uniqueName: 'SUBTYPE_OF_STRUCT_CLASS_IN_IMPLEMENTS',
  );

  ///  Parameters:
  ///  0: the name of the subclass
  ///  1: the name of the class being extended, implemented, or mixed in
  static const FfiCode SUBTYPE_OF_STRUCT_CLASS_IN_WITH = FfiCode(
    'SUBTYPE_OF_STRUCT_CLASS',
    "The class '{0}' can't mix in '{1}' because '{1}' is a subtype of "
        "'Struct', 'Union', or 'AbiSpecificInteger'.",
    correctionMessage:
        "Try extending 'Struct', 'Union', or 'AbiSpecificInteger' directly.",
    hasPublishedDocs: true,
    uniqueName: 'SUBTYPE_OF_STRUCT_CLASS_IN_WITH',
  );

  ///  No parameters.
  static const FfiCode VARIABLE_LENGTH_ARRAY_NOT_LAST = FfiCode(
    'VARIABLE_LENGTH_ARRAY_NOT_LAST',
    "Variable length 'Array's must only occur as the last field of Structs.",
    correctionMessage: "Try adjusting the arguments in the 'Array' annotation.",
    hasPublishedDocs: true,
  );

  /// Initialize a newly created error code to have the given [name].
  const FfiCode(
    String name,
    String problemMessage, {
    super.correctionMessage,
    super.hasPublishedDocs = false,
    super.isUnresolvedIdentifier = false,
    String? uniqueName,
  }) : super(
         name: name,
         problemMessage: problemMessage,
         uniqueName: 'FfiCode.${uniqueName ?? name}',
       );

  @override
  DiagnosticSeverity get severity => DiagnosticType.COMPILE_TIME_ERROR.severity;

  @override
  DiagnosticType get type => DiagnosticType.COMPILE_TIME_ERROR;
}
