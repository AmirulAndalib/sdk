// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/metrics.h"

#include "vm/isolate.h"
#include "vm/json_stream.h"
#include "vm/log.h"
#include "vm/native_entry.h"
#include "vm/object.h"
#include "vm/runtime_entry.h"

namespace dart {

DEFINE_FLAG(bool,
            print_metrics,
            false,
            "Print metrics when isolates (and the VM) are shutdown.");

Metric* Metric::vm_list_head_ = nullptr;

Metric::Metric() : unit_(kCounter), value_(0) {}
Metric::~Metric() {}

void Metric::InitInstance(IsolateGroup* isolate_group,
                          const char* name,
                          const char* description,
                          Unit unit) {
  // Only called once.
  ASSERT(name != nullptr);
  isolate_group_ = isolate_group;
  name_ = name;
  description_ = description;
  unit_ = unit;
}

void Metric::InitInstance(Isolate* isolate,
                          const char* name,
                          const char* description,
                          Unit unit) {
  // Only called once.
  ASSERT(name != nullptr);
  isolate_ = isolate;
  name_ = name;
  description_ = description;
  unit_ = unit;
}

void Metric::InitInstance(const char* name,
                          const char* description,
                          Unit unit) {
  // Only called once.
  ASSERT(name != nullptr);
  name_ = name;
  description_ = description;
  unit_ = unit;
}

#if !defined(PRODUCT)
static const char* UnitString(intptr_t unit) {
  switch (unit) {
    case Metric::kCounter:
      return "counter";
    case Metric::kByte:
      return "byte";
    case Metric::kMicrosecond:
      return "us";
    default:
      UNREACHABLE();
  }
  UNREACHABLE();
  return nullptr;
}

void Metric::PrintJSON(JSONStream* stream) {
  JSONObject obj(stream);
  obj.AddProperty("type", "Counter");
  obj.AddProperty("name", name_);
  obj.AddProperty("description", description_);
  obj.AddProperty("unit", UnitString(unit()));

  if (isolate_ == nullptr && isolate_group_ == nullptr) {
    obj.AddFixedServiceId("vm/metrics/%s", name_);
  } else {
    obj.AddFixedServiceId("metrics/native/%s", name_);
  }

  // TODO(johnmccutchan): Overflow?
  double value_as_double = static_cast<double>(Value());
  obj.AddProperty("value", value_as_double);
}
#endif  // !defined(PRODUCT)

char* Metric::ValueToString(int64_t value, Unit unit) {
  Thread* thread = Thread::Current();
  ASSERT(thread != nullptr);
  Zone* zone = thread->zone();
  ASSERT(zone != nullptr);
  switch (unit) {
    case kCounter:
      return zone->PrintToString("%" Pd64 "", value);
    case kByte: {
      const char* scaled_suffix = "B";
      double scaled_value = static_cast<double>(value);
      if (value > GB) {
        scaled_suffix = "GB";
        scaled_value /= GB;
      } else if (value > MB) {
        scaled_suffix = "MB";
        scaled_value /= MB;
      } else if (value > KB) {
        scaled_suffix = "kB";
        scaled_value /= KB;
      }
      return zone->PrintToString("%.3f %s (%" Pd64 " B)", scaled_value,
                                 scaled_suffix, value);
    }
    case kMicrosecond: {
      const char* scaled_suffix = "us";
      double scaled_value = static_cast<double>(value);
      if (value > kMicrosecondsPerSecond) {
        scaled_suffix = "s";
        scaled_value /= kMicrosecondsPerSecond;
      } else if (value > kMicrosecondsPerMillisecond) {
        scaled_suffix = "ms";
        scaled_value /= kMicrosecondsPerMillisecond;
      }
      return zone->PrintToString("%.3f %s (%" Pd64 " us)", scaled_value,
                                 scaled_suffix, value);
    }
    default:
      UNREACHABLE();
      return nullptr;
  }
}

char* Metric::ToString() {
  Thread* thread = Thread::Current();
  ASSERT(thread != nullptr);
  Zone* zone = thread->zone();
  ASSERT(zone != nullptr);
  return zone->PrintToString("%s %s", name(), ValueToString(Value(), unit()));
}

int64_t MetricHeapOldUsed::Value() const {
  ASSERT(isolate_group() == IsolateGroup::Current());
  return isolate_group()->heap()->UsedInWords(Heap::kOld) * kWordSize;
}

int64_t MetricHeapOldCapacity::Value() const {
  ASSERT(isolate_group() == IsolateGroup::Current());
  return isolate_group()->heap()->CapacityInWords(Heap::kOld) * kWordSize;
}

int64_t MetricHeapOldExternal::Value() const {
  ASSERT(isolate_group() == IsolateGroup::Current());
  return isolate_group()->heap()->ExternalInWords(Heap::kOld) * kWordSize;
}

int64_t MetricHeapNewUsed::Value() const {
  ASSERT(isolate_group() == IsolateGroup::Current());
  // UsedInWords requires a safepoint to access all the TLAB pointers without a
  // data race, so coarsen this metric to capacity. Preferable to locking during
  // new-space allocation.
  return isolate_group()->heap()->CapacityInWords(Heap::kNew) * kWordSize;
}

int64_t MetricHeapNewCapacity::Value() const {
  ASSERT(isolate_group() == IsolateGroup::Current());
  return isolate_group()->heap()->CapacityInWords(Heap::kNew) * kWordSize;
}

int64_t MetricHeapNewExternal::Value() const {
  ASSERT(isolate_group() == IsolateGroup::Current());
  return isolate_group()->heap()->ExternalInWords(Heap::kNew) * kWordSize;
}

int64_t MetricHeapUsed::Value() const {
  ASSERT(isolate_group() == IsolateGroup::Current());
  return isolate_group()->heap()->UsedInWords(Heap::kNew) * kWordSize +
         isolate_group()->heap()->UsedInWords(Heap::kOld) * kWordSize;
}

int64_t MetricIsolateCount::Value() const {
  return Isolate::IsolateListLength();
}

#if !defined(PRODUCT)
int64_t MetricCurrentRSS::Value() const {
  return Service::CurrentRSS();
}

int64_t MetricPeakRSS::Value() const {
  return Service::MaxRSS();
}
#endif  // !defined(PRODUCT)

MaxMetric::MaxMetric() : Metric() {
  set_value(kMinInt64);
}

void MaxMetric::SetValue(int64_t new_value) {
  if (new_value > value()) {
    set_value(new_value);
  }
}

MinMetric::MinMetric() : Metric() {
  set_value(kMaxInt64);
}

void MinMetric::SetValue(int64_t new_value) {
  if (new_value < value()) {
    set_value(new_value);
  }
}

}  // namespace dart
