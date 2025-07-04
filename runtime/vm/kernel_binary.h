// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_KERNEL_BINARY_H_
#define RUNTIME_VM_KERNEL_BINARY_H_

#if !defined(DART_PRECOMPILED_RUNTIME)

#include "platform/unaligned.h"
#include "vm/kernel.h"
#include "vm/object.h"

namespace dart {
namespace kernel {

// Keep in sync with package:kernel/lib/binary/tag.dart,
// package:kernel/binary.md.

static const uint32_t kMagicProgramFile = 0x90ABCDEFu;
static const uint32_t kSupportedKernelFormatVersion = 125;

// Keep in sync with package:kernel/lib/binary/tag.dart
#define KERNEL_TAG_LIST(V)                                                     \
  V(Nothing, 0)                                                                \
  V(Something, 1)                                                              \
  V(Class, 2)                                                                  \
  V(Extension, 115)                                                            \
  V(ExtensionTypeDeclaration, 85)                                              \
  V(FunctionNode, 3)                                                           \
  V(Field, 4)                                                                  \
  V(Constructor, 5)                                                            \
  V(Procedure, 6)                                                              \
  V(InvalidInitializer, 7)                                                     \
  V(FieldInitializer, 8)                                                       \
  V(SuperInitializer, 9)                                                       \
  V(RedirectingInitializer, 10)                                                \
  V(LocalInitializer, 11)                                                      \
  V(AssertInitializer, 12)                                                     \
  V(CheckLibraryIsLoaded, 13)                                                  \
  V(LoadLibrary, 14)                                                           \
  V(EqualsNull, 15)                                                            \
  V(EqualsCall, 16)                                                            \
  V(StaticTearOff, 17)                                                         \
  V(ConstStaticInvocation, 18)                                                 \
  V(InvalidExpression, 19)                                                     \
  V(VariableGet, 20)                                                           \
  V(VariableSet, 21)                                                           \
  V(AbstractSuperPropertyGet, 22)                                              \
  V(AbstractSuperPropertySet, 23)                                              \
  V(SuperPropertyGet, 24)                                                      \
  V(SuperPropertySet, 25)                                                      \
  V(StaticGet, 26)                                                             \
  V(StaticSet, 27)                                                             \
  V(AbstractSuperMethodInvocation, 28)                                         \
  V(SuperMethodInvocation, 29)                                                 \
  V(StaticInvocation, 30)                                                      \
  V(ConstructorInvocation, 31)                                                 \
  V(ConstConstructorInvocation, 32)                                            \
  V(Not, 33)                                                                   \
  V(NullCheck, 117)                                                            \
  V(LogicalExpression, 34)                                                     \
  V(ConditionalExpression, 35)                                                 \
  V(StringConcatenation, 36)                                                   \
  V(ListConcatenation, 111)                                                    \
  V(SetConcatenation, 112)                                                     \
  V(MapConcatenation, 113)                                                     \
  V(InstanceCreation, 114)                                                     \
  V(FileUriExpression, 116)                                                    \
  V(IsExpression, 37)                                                          \
  V(AsExpression, 38)                                                          \
  V(StringLiteral, 39)                                                         \
  V(DoubleLiteral, 40)                                                         \
  V(TrueLiteral, 41)                                                           \
  V(FalseLiteral, 42)                                                          \
  V(NullLiteral, 43)                                                           \
  V(SymbolLiteral, 44)                                                         \
  V(TypeLiteral, 45)                                                           \
  V(ThisExpression, 46)                                                        \
  V(Rethrow, 47)                                                               \
  V(Throw, 48)                                                                 \
  V(ListLiteral, 49)                                                           \
  V(SetLiteral, 109)                                                           \
  V(MapLiteral, 50)                                                            \
  V(AwaitExpression, 51)                                                       \
  V(FunctionExpression, 52)                                                    \
  V(Let, 53)                                                                   \
  V(BlockExpression, 82)                                                       \
  V(Instantiation, 54)                                                         \
  V(PositiveIntLiteral, 55)                                                    \
  V(NegativeIntLiteral, 56)                                                    \
  V(BigIntLiteral, 57)                                                         \
  V(ConstListLiteral, 58)                                                      \
  V(ConstSetLiteral, 110)                                                      \
  V(ConstMapLiteral, 59)                                                       \
  V(ConstructorTearOff, 60)                                                    \
  V(TypedefTearOff, 83)                                                        \
  V(RedirectingFactoryTearOff, 84)                                             \
  V(RecordIndexGet, 101)                                                       \
  V(RecordNameGet, 102)                                                        \
  V(RecordLiteral, 104)                                                        \
  V(ConstRecordLiteral, 105)                                                   \
  V(ExpressionStatement, 61)                                                   \
  V(Block, 62)                                                                 \
  V(EmptyStatement, 63)                                                        \
  V(AssertStatement, 64)                                                       \
  V(LabeledStatement, 65)                                                      \
  V(BreakStatement, 66)                                                        \
  V(WhileStatement, 67)                                                        \
  V(DoStatement, 68)                                                           \
  V(ForStatement, 69)                                                          \
  V(ForInStatement, 70)                                                        \
  V(SwitchStatement, 71)                                                       \
  V(ContinueSwitchStatement, 72)                                               \
  V(IfStatement, 73)                                                           \
  V(ReturnStatement, 74)                                                       \
  V(TryCatch, 75)                                                              \
  V(TryFinally, 76)                                                            \
  V(YieldStatement, 77)                                                        \
  V(VariableDeclaration, 78)                                                   \
  V(FunctionDeclaration, 79)                                                   \
  V(AsyncForInStatement, 80)                                                   \
  V(AssertBlock, 81)                                                           \
  V(TypedefType, 87)                                                           \
  V(InvalidType, 90)                                                           \
  V(DynamicType, 91)                                                           \
  V(VoidType, 92)                                                              \
  V(InterfaceType, 93)                                                         \
  V(FunctionType, 94)                                                          \
  V(TypeParameterType, 95)                                                     \
  V(SimpleInterfaceType, 96)                                                   \
  V(SimpleFunctionType, 97)                                                    \
  V(NeverType, 98)                                                             \
  V(IntersectionType, 99)                                                      \
  V(RecordType, 100)                                                           \
  V(ExtensionType, 103)                                                        \
  V(ConstantExpression, 106)                                                   \
  V(FutureOrType, 107)                                                         \
  V(FileUriConstantExpression, 108)                                            \
  V(InstanceGet, 118)                                                          \
  V(InstanceSet, 119)                                                          \
  V(InstanceInvocation, 120)                                                   \
  V(InstanceGetterInvocation, 89)                                              \
  V(InstanceTearOff, 121)                                                      \
  V(DynamicGet, 122)                                                           \
  V(DynamicSet, 123)                                                           \
  V(DynamicInvocation, 124)                                                    \
  V(FunctionInvocation, 125)                                                   \
  V(FunctionTearOff, 126)                                                      \
  V(LocalFunctionInvocation, 127)                                              \
  V(AndPattern, 128)                                                           \
  V(AssignedVariablePattern, 129)                                              \
  V(CastPattern, 130)                                                          \
  V(ConstantPattern, 131)                                                      \
  V(InvalidPattern, 132)                                                       \
  V(ListPattern, 133)                                                          \
  V(MapPattern, 134)                                                           \
  V(NamedPattern, 135)                                                         \
  V(NullAssertPattern, 136)                                                    \
  V(NullCheckPattern, 137)                                                     \
  V(ObjectPattern, 138)                                                        \
  V(OrPattern, 139)                                                            \
  V(RecordPattern, 140)                                                        \
  V(RelationalPattern, 141)                                                    \
  V(RestPattern, 142)                                                          \
  V(VariablePattern, 143)                                                      \
  V(WildcardPattern, 144)                                                      \
  V(MapPatternEntry, 145)                                                      \
  V(MapPatternRestEntry, 146)                                                  \
  V(PatternSwitchStatement, 147)                                               \
  V(SwitchExpression, 148)                                                     \
  V(IfCaseStatement, 149)                                                      \
  V(PatternAssignment, 150)                                                    \
  V(PatternVariableDeclaration, 151)                                           \
  V(NullType, 152)                                                             \
  V(SpecializedVariableGet, 224)                                               \
  V(SpecializedVariableSet, 232)                                               \
  V(SpecializedIntLiteral, 240)

static constexpr intptr_t kSpecializedTagHighBits = 0xe0;
static constexpr intptr_t kSpecializedTagMask = 0xf8;
static constexpr intptr_t kSpecializedPayloadMask = 0x7;

enum Tag {
#define DECLARE(Name, value) k##Name = value,
  KERNEL_TAG_LIST(DECLARE)
#undef DECLARE
};

// Keep in sync with package:kernel/lib/binary/tag.dart
enum ConstantTag {
  kNullConstant = 0,
  kBoolConstant = 1,
  kIntConstant = 2,
  kDoubleConstant = 3,
  kStringConstant = 4,
  kSymbolConstant = 5,
  kMapConstant = 6,
  kListConstant = 7,
  kSetConstant = 13,
  kInstanceConstant = 8,
  kInstantiationConstant = 9,
  kStaticTearOffConstant = 10,
  kTypeLiteralConstant = 11,
  // These constants are not expected to be seen by the VM, because all
  // constants are fully evaluated.
  kUnevaluatedConstant = 12,
  kTypedefTearOffConstant = 14,
  kConstructorTearOffConstant = 15,
  kRedirectingFactoryTearOffConstant = 16,
  kRecordConstant = 17,
};

// Keep in sync with package:kernel/lib/ast.dart
enum class KernelNullability : int8_t {
  kUndetermined = 0,
  kNullable = 1,
  kNonNullable = 2,
};

// Keep in sync with package:kernel/lib/ast.dart
enum Variance {
  kUnrelated = 0,
  kCovariant = 1,
  kContravariant = 2,
  kInvariant = 3,
  kLegacyCovariant = 4,
};

// Keep in sync with package:kernel/lib/ast.dart
enum AsExpressionFlags {
  kAsExpressionFlagTypeError = 1 << 0,
  kAsExpressionFlagCovarianceCheck = 1 << 1,
  kAsExpressionFlagForDynamic = 1 << 2,
  kAsExpressionFlagUnchecked = 1 << 3,
};

// Keep in sync with package:kernel/lib/ast.dart
enum InstanceInvocationFlags {
  kInstanceInvocationFlagInvariant = 1 << 0,
  kInstanceInvocationFlagBoundsSafe = 1 << 1,
};

// Keep in sync with package:kernel/lib/ast.dart
enum DynamicInvocationFlags {
  kDynamicInvocationFlagImplicitCall = 1 << 0,
};

// Keep in sync with package:kernel/lib/ast.dart
enum ThrowFlags {
  kThrowForErrorHandling = 1 << 0,
};

// Keep in sync with package:kernel/lib/ast.dart
enum YieldStatementFlags {
  kYieldStatementFlagYieldStar = 1 << 0,
};

// Keep in sync with package:kernel/lib/ast.dart
enum class NamedTypeFlags : uint8_t {
  kIsRequired = 1 << 0,
};

// Keep in sync with package:kernel/lib/ast.dart
enum class FunctionAccessKind {
  kFunction,
  kFunctionType,
  kInapplicable,
  kNullable,
};

static constexpr int SpecializedIntLiteralBias = 3;
static constexpr int KernelFormatVersionOffset = 4;

// These should be kept in sync with the constants in kernels tag.dart.
static constexpr int KernelFixedFieldsBeforeLibraries = 9;
static constexpr int KernelFixedFieldsAfterLibraries = 2;
static inline int KernelNumberOfFixedFields(int numberOfLibraries) {
  return KernelFixedFieldsBeforeLibraries + numberOfLibraries + 1 +
         KernelFixedFieldsAfterLibraries;
}

static constexpr int HeaderSize = 8;  // 'magic', 'formatVersion'.

class Reader : public ValueObject {
 public:
  explicit Reader(const TypedDataBase& typed_data)
      : thread_(Thread::Current()), typed_data_(&typed_data) {
    Init();
  }

  uint32_t ReadFromIndex(intptr_t end_offset,
                         intptr_t fields_before,
                         intptr_t list_size,
                         intptr_t list_index) {
    intptr_t org_offset = offset();
    uint32_t result =
        ReadFromIndexNoReset(end_offset, fields_before, list_size, list_index);
    offset_ = org_offset;
    return result;
  }

  uint32_t ReadUInt32At(intptr_t offset) const {
    ASSERT((size_ >= 4) && (offset >= 0) && (offset <= size_ - 4));
    uint32_t value =
        LoadUnaligned(reinterpret_cast<const uint32_t*>(raw_buffer_ + offset));
    return Utils::BigEndianToHost32(value);
  }

  uint32_t ReadFromIndexNoReset(intptr_t end_offset,
                                intptr_t fields_before,
                                intptr_t list_size,
                                intptr_t list_index) {
    offset_ = end_offset - (fields_before + list_size - list_index) * 4;
    return ReadUInt32();
  }

  uint32_t ReadSingleFieldFromIndexNoReset(intptr_t end_offset,
                                           intptr_t fields_before) {
    offset_ = end_offset - fields_before * 4;
    return ReadUInt32();
  }

  uint32_t ReadUInt32() {
    uint32_t value = ReadUInt32At(offset_);
    offset_ += 4;
    return value;
  }

  double ReadDouble() {
    ASSERT((size_ >= 8) && (offset_ >= 0) && (offset_ <= size_ - 8));
    double value =
        LoadUnaligned(reinterpret_cast<const double*>(&raw_buffer_[offset_]));
    offset_ += 8;
    return value;
  }

  uint32_t ReadUInt() {
    ASSERT((size_ >= 1) && (offset_ >= 0) && (offset_ <= size_ - 1));

    const uint8_t* buffer = raw_buffer_;
    uword byte0 = buffer[offset_];
    if ((byte0 & 0x80) == 0) {
      // 0...
      offset_++;
      return byte0;
    } else if ((byte0 & 0xc0) == 0x80) {
      // 10...
      ASSERT((size_ >= 2) && (offset_ >= 0) && (offset_ <= size_ - 2));
      uint32_t value =
          ((byte0 & ~static_cast<uword>(0x80)) << 8) | (buffer[offset_ + 1]);
      offset_ += 2;
      return value;
    } else {
      // 11...
      ASSERT((size_ >= 4) && (offset_ >= 0) && (offset_ <= size_ - 4));
      uint32_t value = ((byte0 & ~static_cast<uword>(0xc0)) << 24) |
                       (buffer[offset_ + 1] << 16) |
                       (buffer[offset_ + 2] << 8) | (buffer[offset_ + 3] << 0);
      offset_ += 4;
      return value;
    }
  }

  intptr_t ReadSLEB128() {
    ReadStream stream(raw_buffer_, size_, offset_);
    const intptr_t result = stream.ReadSLEB128();
    offset_ = stream.Position();
    return result;
  }

  int64_t ReadSLEB128AsInt64() {
    ReadStream stream(raw_buffer_, size_, offset_);
    const int64_t result = stream.ReadSLEB128<int64_t>();
    offset_ = stream.Position();
    return result;
  }

  /**
   * Read and return a TokenPosition from this reader.
   */
  TokenPosition ReadPosition() {
    // Position is saved as unsigned,
    // but actually ranges from -1 and up (thus the -1)
    intptr_t value = ReadUInt() - 1;
    TokenPosition result = TokenPosition::Deserialize(value);
    max_position_ = TokenPosition::Max(max_position_, result);
    min_position_ = TokenPosition::Min(min_position_, result);
    return result;
  }

  intptr_t ReadListLength() { return ReadUInt(); }

  uint8_t ReadByte() { return raw_buffer_[offset_++]; }

  uint8_t PeekByte() { return raw_buffer_[offset_]; }

  void ReadBytes(uint8_t* buffer, uint8_t size) {
    for (int i = 0; i < size; i++) {
      buffer[i] = ReadByte();
    }
  }

  bool ReadBool() { return (ReadByte() & 1) == 1; }

  uint8_t ReadFlags() { return ReadByte(); }

  static const char* TagName(Tag tag);

  Tag ReadTag(uint8_t* payload = nullptr) {
    uint8_t byte = ReadByte();
    bool has_payload =
        (byte & kSpecializedTagHighBits) == kSpecializedTagHighBits;
    if (has_payload) {
      if (payload != nullptr) {
        *payload = byte & kSpecializedPayloadMask;
      }
      return static_cast<Tag>(byte & kSpecializedTagMask);
    } else {
      return static_cast<Tag>(byte);
    }
  }

  Tag PeekTag(uint8_t* payload = nullptr) {
    uint8_t byte = PeekByte();
    bool has_payload =
        (byte & kSpecializedTagHighBits) == kSpecializedTagHighBits;
    if (has_payload) {
      if (payload != nullptr) {
        *payload = byte & kSpecializedPayloadMask;
      }
      return static_cast<Tag>(byte & kSpecializedTagMask);
    } else {
      return static_cast<Tag>(byte);
    }
  }

  static Nullability ConvertNullability(KernelNullability kernel_nullability) {
    switch (kernel_nullability) {
      case KernelNullability::kNullable:
        return Nullability::kNullable;
      case KernelNullability::kNonNullable:
      case KernelNullability::kUndetermined:
        return Nullability::kNonNullable;
    }
    UNREACHABLE();
  }

  Nullability ReadNullability() {
    const uint8_t byte = ReadByte();
    return ConvertNullability(static_cast<KernelNullability>(byte));
  }

  Variance ReadVariance() {
    uint8_t byte = ReadByte();
    return static_cast<Variance>(byte);
  }

  void EnsureEnd() {
    if (offset_ != size_) {
      FATAL(
          "Reading Kernel file: Expected to be at EOF "
          "(offset: %" Pd ", size: %" Pd ")",
          offset_, size_);
    }
  }

  // The largest position read yet (since last reset).
  // This is automatically updated when calling ReadPosition,
  // but can be overwritten (e.g. via the PositionScope class).
  TokenPosition max_position() { return max_position_; }
  // The smallest position read yet (since last reset).
  // This is automatically updated when calling ReadPosition,
  // but can be overwritten (e.g. via the PositionScope class).
  TokenPosition min_position() { return min_position_; }

  // A canonical name reference of -1 indicates none (for optional names), not
  // the root name as in the canonical name table.
  NameIndex ReadCanonicalNameReference() { return NameIndex(ReadUInt() - 1); }

  const TypedDataBase* typed_data() { return typed_data_; }

  intptr_t offset() const { return offset_; }
  void set_offset(intptr_t offset) {
    ASSERT(offset < size_);
    offset_ = offset;
  }
  intptr_t size() const { return size_; }

  TypedDataViewPtr ViewFromTo(intptr_t start, intptr_t end) {
    return typed_data_->ViewFromTo(start, end, Heap::kOld);
  }

  const uint8_t* BufferAt(intptr_t offset) {
    ASSERT((offset >= 0) && (offset < size_));
    return &raw_buffer_[offset];
  }

  TypedDataPtr ReadLineStartsData(intptr_t line_start_count);

 private:
  friend class Program;
  friend class AlternativeReadingScopeWithNewData;
  friend class AlternativeReadingScope;

  Reader(const uint8_t* buffer, intptr_t size)
      : thread_(nullptr), raw_buffer_(buffer), size_(size) {}

  void Init() {
    if (typed_data_->IsNull()) {
      raw_buffer_ = nullptr;
      size_ = 0;
    } else {
      ASSERT(typed_data_->IsExternalOrExternalView());
      raw_buffer_ = reinterpret_cast<uint8_t*>(typed_data_->DataAddr(0));
      size_ = typed_data_->LengthInBytes();
    }
    offset_ = 0;
  }

  Thread* thread_ = nullptr;

  // A external typed data or a view on an external typed data.
  const TypedDataBase* typed_data_ = nullptr;

  // The raw data size/length of [typed_data_].
  const uint8_t* raw_buffer_ = nullptr;
  intptr_t size_ = 0;

  intptr_t offset_ = 0;
  TokenPosition max_position_ = TokenPosition::kNoSource;
  TokenPosition min_position_ = TokenPosition::kNoSource;
  intptr_t current_script_id_ = -1;

  friend class PositionScope;
  friend class Program;
};

// A helper class that saves the current reader position, goes to another reader
// position, and upon destruction, resets to the original reader position.
class AlternativeReadingScope {
 public:
  AlternativeReadingScope(Reader* reader, intptr_t new_position)
      : reader_(reader), saved_offset_(reader_->offset_) {
    reader_->offset_ = new_position;
  }

  explicit AlternativeReadingScope(Reader* reader)
      : reader_(reader), saved_offset_(reader_->offset_) {}

  ~AlternativeReadingScope() { reader_->offset_ = saved_offset_; }

  intptr_t saved_offset() { return saved_offset_; }

 private:
  Reader* const reader_;
  const intptr_t saved_offset_;

  DISALLOW_COPY_AND_ASSIGN(AlternativeReadingScope);
};

// Similar to AlternativeReadingScope, but also switches reading to another
// typed data array.
class AlternativeReadingScopeWithNewData {
 public:
  AlternativeReadingScopeWithNewData(Reader* reader,
                                     const TypedDataBase* new_typed_data,
                                     intptr_t new_position)
      : reader_(reader),
        saved_size_(reader_->size_),
        saved_raw_buffer_(reader_->raw_buffer_),
        saved_typed_data_(reader_->typed_data_),
        saved_offset_(reader_->offset_) {
    reader_->typed_data_ = new_typed_data;
    reader_->Init();
    reader_->offset_ = new_position;
  }

  ~AlternativeReadingScopeWithNewData() {
    reader_->raw_buffer_ = saved_raw_buffer_;
    reader_->typed_data_ = saved_typed_data_;
    reader_->size_ = saved_size_;
    reader_->offset_ = saved_offset_;
  }

  intptr_t saved_offset() { return saved_offset_; }

 private:
  Reader* reader_;
  intptr_t saved_size_;
  const uint8_t* saved_raw_buffer_;
  const TypedDataBase* saved_typed_data_;
  intptr_t saved_offset_;

  DISALLOW_COPY_AND_ASSIGN(AlternativeReadingScopeWithNewData);
};

// A helper class that resets the readers min and max positions both upon
// initialization and upon destruction, i.e. when created the min an max
// positions will be reset to "noSource", when destructing the min and max will
// be reset to have they value they would have had, if they hadn't been reset in
// the first place.
class PositionScope {
 public:
  explicit PositionScope(Reader* reader)
      : reader_(reader),
        min_(reader->min_position_),
        max_(reader->max_position_) {
    reader->min_position_ = reader->max_position_ = TokenPosition::kNoSource;
  }

  ~PositionScope() {
    reader_->min_position_ = TokenPosition::Min(reader_->min_position_, min_);
    reader_->max_position_ = TokenPosition::Max(reader_->max_position_, max_);
  }

 private:
  Reader* reader_;
  TokenPosition min_;
  TokenPosition max_;

  DISALLOW_COPY_AND_ASSIGN(PositionScope);
};

}  // namespace kernel
}  // namespace dart

#endif  // !defined(DART_PRECOMPILED_RUNTIME)
#endif  // RUNTIME_VM_KERNEL_BINARY_H_
