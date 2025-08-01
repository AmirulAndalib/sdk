// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/globals.h"
#if defined(SUPPORT_TIMELINE)

#include "vm/timeline.h"

#include <errno.h>
#include <fcntl.h>

#include <cstdlib>
#include <functional>
#include <memory>
#include <tuple>
#include <utility>

#if defined(DART_HOST_OS_MACOS)
#include <os/signpost.h>
#endif

#include "platform/atomic.h"
#include "platform/hashmap.h"
#include "vm/isolate.h"
#include "vm/json_stream.h"
#include "vm/lockers.h"
#include "vm/log.h"
#include "vm/object.h"
#include "vm/service.h"
#include "vm/service_event.h"
#include "vm/thread.h"

#if defined(SUPPORT_PERFETTO) && !defined(PRODUCT)
#include "perfetto/ext/tracing/core/trace_packet.h"
#include "vm/perfetto_utils.h"
#include "vm/protos/perfetto/common/builtin_clock.pbzero.h"
#include "vm/protos/perfetto/trace/clock_snapshot.pbzero.h"
#include "vm/protos/perfetto/trace/interned_data/interned_data.pbzero.h"
#include "vm/protos/perfetto/trace/trace_packet.pbzero.h"
#include "vm/protos/perfetto/trace/track_event/debug_annotation.pbzero.h"
#include "vm/protos/perfetto/trace/track_event/process_descriptor.pbzero.h"
#include "vm/protos/perfetto/trace/track_event/thread_descriptor.pbzero.h"
#include "vm/protos/perfetto/trace/track_event/track_descriptor.pbzero.h"
#include "vm/protos/perfetto/trace/track_event/track_event.pbzero.h"
#endif  // defined(SUPPORT_PERFETTO) && !defined(PRODUCT)

namespace dart {

#if defined(PRODUCT)
#define DEFAULT_TIMELINE_RECORDER "none"
#define SUPPORTED_TIMELINE_RECORDERS "systrace, file, callback"
#else
#define DEFAULT_TIMELINE_RECORDER "ring"
#if defined(SUPPORT_PERFETTO)
#define SUPPORTED_TIMELINE_RECORDERS                                           \
  "ring, endless, startup, systrace, file, callback, perfettofile"
#else
#define SUPPORTED_TIMELINE_RECORDERS                                           \
  "ring, endless, startup, systrace, file, callback"
#endif
#endif

DEFINE_FLAG(bool, complete_timeline, false, "Record the complete timeline");
DEFINE_FLAG(bool, startup_timeline, false, "Record the startup timeline");
// TODO(derekx): Remove this flag in Dart 3.4.
DEFINE_FLAG(
    bool,
    systrace_timeline,
    false,
    "Record the timeline to the platform's tracing service if there is one");
DEFINE_FLAG(bool, trace_timeline, false, "Trace timeline backend");
DEFINE_FLAG(charp,
            timeline_dir,
            nullptr,
            "Enable all timeline trace streams and output VM global trace "
            "into specified directory. This flag is ignored by the file and "
            "perfetto recorders.");
DEFINE_FLAG(charp,
            timeline_streams,
            nullptr,
            "Comma separated list of timeline streams to record. "
            "Valid values: all, API, Compiler, CompilerVerbose, Dart, "
            "Debugger, Embedder, GC, Isolate, Microtask, and VM.");
DEFINE_FLAG(charp,
            timeline_recorder,
            DEFAULT_TIMELINE_RECORDER,
            "Select the timeline recorder used. "
            "Valid values: none, " SUPPORTED_TIMELINE_RECORDERS)
DEFINE_FLAG(bool,
            intern_strings_when_writing_perfetto_timeline,
            false,
            "Intern strings when writing timeline in perfetto format.")

// Implementation notes:
//
// Writing events:
// |TimelineEvent|s are written into |TimelineEventBlock|s. Each |Thread| caches
// a |TimelineEventBlock| object so that it can write events without
// synchronizing with other threads in the system. Even though the |Thread| owns
// the |TimelineEventBlock| the block may need to be reclaimed by the reporting
// system. To support that, a |Thread| must hold its |timeline_block_lock_|
// when operating on the |TimelineEventBlock|. This lock will only ever be
// busy if blocks are being reclaimed by the reporting system.
//
// Reporting:
// When requested, the timeline is serialized in either Chrome's JSON trace
// format (https://goo.gl/hDZw5M) or Perfetto's proto trace format. In both
// cases, it may be that a thread has a |TimelineEventBlock| cached in TLS
// partially filled with events. In order to report a complete timeline, the
// cached |TimelineEventBlock|s need to be reclaimed.
//
// Reclaiming open |TimelineEventBlock|s from threads:
//
// Each |Thread| can have one |TimelineEventBlock| cached in it.
//
// To reclaim blocks, we iterate over all threads and remove the cached
// |TimelineEventBlock| from each thread. This is safe because we hold the
// |Thread|'s |timeline_block_lock_| meaning the block can't be being modified.
// When clearing the reclaimed blocks, or serializing the events in them, we
// hold |TimelineEventRecorder::lock_| before reclaiming the blocks, to prevent
// reclaimed blocks from being handed out again until we release it.
//
// Locking notes:
// The following locks are used by the timeline system:
// - |TimelineEventRecorder::lock_| This lock is held whenever a
// |TimelineEventBlock| is being requested or reclaimed.
// - |Thread::timeline_block_lock_| This lock is held whenever a |Thread|'s
// cached block is being operated on.
// - |Thread::thread_list_lock_| This lock is held when iterating over
// |Thread|s.
//
// Locks must always be taken in the following order:
//   |Thread::thread_list_lock_|
//     |TimelineEventRecorder::lock_|
//       |Thread::timeline_block_lock_|
//

std::atomic<RecorderSynchronizationLock::RecorderState>
    RecorderSynchronizationLock::recorder_state_ = {
        RecorderSynchronizationLock::kUninitialized};
std::atomic<intptr_t> RecorderSynchronizationLock::outstanding_event_writes_ = {
    0};

static TimelineEventRecorder* CreateDefaultTimelineRecorder() {
#if defined(PRODUCT)
  return new TimelineEventNopRecorder();
#else
  return new TimelineEventRingRecorder();
#endif
}

#if !defined(PRODUCT) && defined(SUPPORT_PERFETTO)
static TimelineEventRecorder* CreateTimelineEventPerfettoFileRecorder(
    const char* filename);
#endif

static TimelineEventRecorder* CreateTimelineRecorder() {
  ASSERT(FLAG_timeline_recorder != nullptr);
  const char* flag = FLAG_timeline_recorder;

  if (FLAG_systrace_timeline) {
    OS::PrintErr(
        "Warning: the --systrace-timeline flag is deprecated and will "
        "be removed in Dart SDK v3.4. Please use --timeline-recorder=systrace "
        "instead.\n");
    flag = "systrace";
  } else if (FLAG_timeline_dir != nullptr || FLAG_complete_timeline) {
    // Some flags require that we use the endless recorder.
    flag = "endless";
  } else if (FLAG_startup_timeline) {
    flag = "startup";
  }

  if (strcmp("none", flag) == 0) {
    return new TimelineEventNopRecorder();
  }

  // Systrace recorder.
  if (strcmp("systrace", flag) == 0) {
#if defined(DART_HOST_OS_LINUX) || defined(DART_HOST_OS_ANDROID)
    return new TimelineEventSystraceRecorder();
#elif defined(DART_HOST_OS_MACOS)
    return new TimelineEventMacosRecorder();
#elif defined(DART_HOST_OS_FUCHSIA)
    return new TimelineEventFuchsiaRecorder();
#else
    // Not supported. A warning will be emitted below.
#endif
  }

  if (Utils::StrStartsWith(flag, "file") &&
      (flag[4] == '\0' || flag[4] == ':' || flag[4] == '=')) {
    const char* filename = flag[4] == '\0' ? "dart-timeline.json" : &flag[5];
    free(const_cast<char*>(FLAG_timeline_dir));
    FLAG_timeline_dir = nullptr;
    return new TimelineEventFileRecorder(filename);
  }

  if (strcmp("callback", flag) == 0) {
    return new TimelineEventEmbedderCallbackRecorder();
  }

#if !defined(PRODUCT)
#if defined(SUPPORT_PERFETTO)
  // The Perfetto file recorder is disabled in PRODUCT mode to avoid the large
  // binary size increase that it brings.
  {
    const intptr_t kPrefixLength = 12;
    if (Utils::StrStartsWith(flag, "perfettofile") &&
        (flag[kPrefixLength] == '\0' || flag[kPrefixLength] == ':' ||
         flag[kPrefixLength] == '=')) {
      const char* filename = flag[kPrefixLength] == '\0'
                                 ? "dart.perfetto-trace"
                                 : &flag[kPrefixLength + 1];
      free(const_cast<char*>(FLAG_timeline_dir));
      FLAG_timeline_dir = nullptr;
      return CreateTimelineEventPerfettoFileRecorder(filename);
    }
  }
#endif  // defined(SUPPORT_PERFETTO)

  // Recorders below do nothing useful in PRODUCT mode. You can't extract
  // information available in them without vm-service.
  if (strcmp("endless", flag) == 0) {
    return new TimelineEventEndlessRecorder();
  }

  if (strcmp("startup", flag) == 0) {
    return new TimelineEventStartupRecorder();
  }

  if (strcmp("ring", flag) == 0) {
    return new TimelineEventRingRecorder();
  }
#endif  // !defined(PRODUCT)

  if (strlen(flag) > 0 && strcmp(flag, DEFAULT_TIMELINE_RECORDER) != 0) {
    OS::PrintErr(
        "Warning: requested %s timeline recorder which is not supported, "
        "defaulting to the " DEFAULT_TIMELINE_RECORDER " recorder\n",
        flag);
  }

  return CreateDefaultTimelineRecorder();
}

// Returns a caller freed array of stream names in FLAG_timeline_streams.
static MallocGrowableArray<char*>* GetEnabledByDefaultTimelineStreams() {
  MallocGrowableArray<char*>* result = new MallocGrowableArray<char*>();
  if (FLAG_timeline_streams == nullptr) {
    // Nothing set.
    return result;
  }
  char* save_ptr;  // Needed for strtok_r.
  // strtok modifies arg 1 so we make a copy of it.
  char* streams = Utils::StrDup(FLAG_timeline_streams);
  char* token = strtok_r(streams, ",", &save_ptr);
  while (token != nullptr) {
    result->Add(Utils::StrDup(token));
    token = strtok_r(nullptr, ",", &save_ptr);
  }
  free(streams);
  return result;
}

// Frees the result of |GetEnabledByDefaultTimelineStreams|.
static void FreeEnabledByDefaultTimelineStreams(
    MallocGrowableArray<char*>* streams) {
  if (streams == nullptr) {
    return;
  }
  for (intptr_t i = 0; i < streams->length(); i++) {
    free((*streams)[i]);
  }
  delete streams;
}

// Returns true if |streams| contains |stream| or "all". Not case sensitive.
static bool HasStream(MallocGrowableArray<char*>* streams, const char* stream) {
  if ((FLAG_timeline_dir != nullptr) || FLAG_complete_timeline ||
      FLAG_startup_timeline) {
    return true;
  }
  for (intptr_t i = 0; i < streams->length(); i++) {
    const char* checked_stream = (*streams)[i];
    if ((strstr(checked_stream, "all") != nullptr) ||
        (strstr(checked_stream, stream) != nullptr)) {
      return true;
    }
  }
  return false;
}

void Timeline::Init() {
  ASSERT(recorder_ == nullptr);
  recorder_ = CreateTimelineRecorder();

  RecorderSynchronizationLock::Init();

  // The following is needed to backfill information about any |OSThread|s that
  // were initialized before this point.
  OSThreadIterator it;
  while (it.HasNext()) {
    OSThread& thread = *it.Next();
    recorder_->AddTrackMetadataBasedOnThread(
        OS::ProcessId(), OSThread::ThreadIdToIntPtr(thread.trace_id()),
        thread.name());
  }
  if (FLAG_trace_timeline) {
    OS::PrintErr("Using the %s timeline recorder.\n", recorder_->name());
  }
  ASSERT(recorder_ != nullptr);
  enabled_streams_ = GetEnabledByDefaultTimelineStreams();
// Global overrides.
#define TIMELINE_STREAM_FLAG_DEFAULT(name, ...)                                \
  stream_##name##_.set_enabled(HasStream(enabled_streams_, #name));
  TIMELINE_STREAM_LIST(TIMELINE_STREAM_FLAG_DEFAULT)
#undef TIMELINE_STREAM_FLAG_DEFAULT
}

void Timeline::Cleanup() {
  ASSERT(recorder_ != nullptr);

#ifndef PRODUCT
  if (FLAG_timeline_dir != nullptr) {
    recorder_->WriteTo(FLAG_timeline_dir);
  }
#endif

// Disable global streams.
#define TIMELINE_STREAM_DISABLE(name, ...)                                     \
  Timeline::stream_##name##_.set_enabled(false);
  TIMELINE_STREAM_LIST(TIMELINE_STREAM_DISABLE)
#undef TIMELINE_STREAM_DISABLE
  RecorderSynchronizationLock::WaitForShutdown();
  Timeline::Clear();
  delete recorder_;
  recorder_ = nullptr;
  if (enabled_streams_ != nullptr) {
    FreeEnabledByDefaultTimelineStreams(enabled_streams_);
    enabled_streams_ = nullptr;
  }
}

void Timeline::ReclaimCachedBlocksFromThreads() {
  RecorderSynchronizationLockScope ls;
  TimelineEventRecorder* recorder = Timeline::recorder();
  if (recorder == nullptr || ls.IsUninitialized()) {
    return;
  }
  ASSERT(recorder != nullptr);
  // Iterate over threads.
  OSThreadIterator it;
  while (it.HasNext()) {
    OSThread* thread = it.Next();
    MutexLocker ml(thread->timeline_block_lock());
    // Grab block and clear it.
    TimelineEventBlock* block = thread->TimelineBlockLocked();
    thread->SetTimelineBlockLocked(nullptr);
    recorder->FinishBlock(block);
  }
}

#ifndef PRODUCT
void Timeline::PrintFlagsToJSONArray(JSONArray* arr) {
#define ADD_RECORDED_STREAM_NAME(name, ...)                                    \
  if (stream_##name##_.enabled()) {                                            \
    arr->AddValue(#name);                                                      \
  }
  TIMELINE_STREAM_LIST(ADD_RECORDED_STREAM_NAME);
#undef ADD_RECORDED_STREAM_NAME
}

void Timeline::PrintFlagsToJSON(JSONStream* js) {
  JSONObject obj(js);
  obj.AddProperty("type", "TimelineFlags");
  RecorderSynchronizationLockScope ls;
  TimelineEventRecorder* recorder = Timeline::recorder();
  if (recorder == nullptr || !ls.IsActive()) {
    obj.AddProperty("recorderName", "null");
  } else {
    obj.AddProperty("recorderName", recorder->name());
  }
  {
    JSONArray availableStreams(&obj, "availableStreams");
#define ADD_STREAM_NAME(name, ...) availableStreams.AddValue(#name);
    TIMELINE_STREAM_LIST(ADD_STREAM_NAME);
#undef ADD_STREAM_NAME
  }
  {
    JSONArray recordedStreams(&obj, "recordedStreams");
#define ADD_RECORDED_STREAM_NAME(name, ...)                                    \
  if (stream_##name##_.enabled()) {                                            \
    recordedStreams.AddValue(#name);                                           \
  }
    TIMELINE_STREAM_LIST(ADD_RECORDED_STREAM_NAME);
#undef ADD_RECORDED_STREAM_NAME
  }
}
#endif

void Timeline::Clear() {
  RecorderSynchronizationLockScope ls;
  TimelineEventRecorder* recorder = Timeline::recorder();
  if (recorder == nullptr || ls.IsUninitialized()) {
    return;
  }
  ASSERT(recorder != nullptr);
  // Acquire the recorder's lock to prevent the reclaimed blocks from being
  // handed out again until they have been cleared.
  MutexLocker ml(&recorder->lock_);
  ReclaimCachedBlocksFromThreads();
  recorder->ClearLocked();
}

void TimelineEventArguments::SetNumArguments(intptr_t length) {
  if (length == length_) {
    return;
  }
  if (length == 0) {
    Free();
    return;
  }
  if (buffer_ == nullptr) {
    // calloc already nullifies
    buffer_ = reinterpret_cast<TimelineEventArgument*>(
        calloc(sizeof(TimelineEventArgument), length));
  } else {
    for (intptr_t i = length; i < length_; ++i) {
      free(buffer_[i].value);
      buffer_[i].value = nullptr;
      buffer_[i].name = nullptr;
    }
    buffer_ = reinterpret_cast<TimelineEventArgument*>(
        realloc(buffer_, sizeof(TimelineEventArgument) * length));
    if (length > length_) {
      memset(buffer_ + length_, 0,
             sizeof(TimelineEventArgument) * (length - length_));
    }
  }
  length_ = length;
}

void TimelineEventArguments::SetArgument(intptr_t i,
                                         const char* name,
                                         char* argument) {
  ASSERT(i >= 0);
  ASSERT(i < length_);
  buffer_[i].name = name;
  buffer_[i].value = argument;
}

void TimelineEventArguments::CopyArgument(intptr_t i,
                                          const char* name,
                                          const char* argument) {
  SetArgument(i, name, Utils::StrDup(argument));
}

void TimelineEventArguments::FormatArgument(intptr_t i,
                                            const char* name,
                                            const char* fmt,
                                            va_list args) {
  ASSERT(i >= 0);
  ASSERT(i < length_);
  va_list measure_args;
  va_copy(measure_args, args);
  intptr_t len = Utils::VSNPrint(nullptr, 0, fmt, measure_args);
  va_end(measure_args);

  char* buffer = reinterpret_cast<char*>(malloc(len + 1));
  va_list print_args;
  va_copy(print_args, args);
  Utils::VSNPrint(buffer, (len + 1), fmt, print_args);
  va_end(print_args);

  SetArgument(i, name, buffer);
}

void TimelineEventArguments::StealArguments(TimelineEventArguments* arguments) {
  Free();
  length_ = arguments->length_;
  buffer_ = arguments->buffer_;
  arguments->length_ = 0;
  arguments->buffer_ = nullptr;
}

void TimelineEventArguments::Free() {
  if (buffer_ == nullptr) {
    return;
  }
  for (intptr_t i = 0; i < length_; i++) {
    free(buffer_[i].value);
  }
  free(buffer_);
  buffer_ = nullptr;
  length_ = 0;
}

TimelineEventRecorder* Timeline::recorder_ = nullptr;
Dart_TimelineRecorderCallback Timeline::callback_ = nullptr;
MallocGrowableArray<char*>* Timeline::enabled_streams_ = nullptr;
bool Timeline::recorder_discards_clock_values_ = false;

#define TIMELINE_STREAM_DEFINE(name, fuchsia_name, static_labels)              \
  TimelineStream Timeline::stream_##name##_(#name, fuchsia_name,               \
                                            static_labels, false);
TIMELINE_STREAM_LIST(TIMELINE_STREAM_DEFINE)
#undef TIMELINE_STREAM_DEFINE

TimelineEvent::TimelineEvent()
    : timestamp0_(0),
      timestamp1_or_id_(0),
      flow_id_count_(0),
      flow_ids_(),
      state_(0),
      label_(nullptr),
      stream_(nullptr),
      thread_(OSThread::kInvalidThreadId),
      isolate_id_(ILLEGAL_ISOLATE_ID),
      isolate_group_id_(ILLEGAL_ISOLATE_GROUP_ID) {}

TimelineEvent::~TimelineEvent() {
  Reset();
}

void TimelineEvent::Reset() {
  timestamp0_ = 0;
  timestamp1_or_id_ = 0;
  flow_id_count_ = 0;
  flow_ids_.reset();
  if (owns_label() && label_ != nullptr) {
    free(const_cast<char*>(label_));
  }
  label_ = nullptr;
  stream_ = nullptr;
  thread_ = OSThread::kInvalidThreadId;
  isolate_id_ = ILLEGAL_ISOLATE_ID;
  isolate_group_id_ = ILLEGAL_ISOLATE_GROUP_ID;
  arguments_.Free();
  state_ = 0;
}

void TimelineEvent::AsyncBegin(const char* label,
                               int64_t async_id,
                               int64_t micros) {
  Init(kAsyncBegin, label);
  set_timestamp0(micros);
  // Overload timestamp1_ with the async_id.
  set_timestamp1_or_id(async_id);
}

void TimelineEvent::AsyncInstant(const char* label,
                                 int64_t async_id,
                                 int64_t micros) {
  Init(kAsyncInstant, label);
  set_timestamp0(micros);
  // Overload timestamp1_ with the async_id.
  set_timestamp1_or_id(async_id);
}

void TimelineEvent::AsyncEnd(const char* label,
                             int64_t async_id,
                             int64_t micros) {
  Init(kAsyncEnd, label);
  set_timestamp0(micros);
  // Overload timestamp1_ with the async_id.
  set_timestamp1_or_id(async_id);
}

void TimelineEvent::DurationBegin(const char* label, int64_t micros) {
  Init(kDuration, label);
  set_timestamp0(micros);
}

void TimelineEvent::Instant(const char* label, int64_t micros) {
  Init(kInstant, label);
  set_timestamp0(micros);
}

void TimelineEvent::Duration(const char* label,
                             int64_t start_micros,
                             int64_t end_micros) {
  Init(kDuration, label);
  set_timestamp0(start_micros);
  set_timestamp1_or_id(end_micros);
}

void TimelineEvent::Begin(const char* label, int64_t id, int64_t micros) {
  Init(kBegin, label);
  set_timestamp0(micros);
  // Overload timestamp1_ with the event ID. This is required for the MacOS
  // recorder to work.
  set_timestamp1_or_id(id);
}

void TimelineEvent::End(const char* label, int64_t id, int64_t micros) {
  Init(kEnd, label);
  set_timestamp0(micros);
  // Overload timestamp1_ with the event ID. This is required for the MacOS
  // recorder to work.
  set_timestamp1_or_id(id);
}

void TimelineEvent::Counter(const char* label, int64_t micros) {
  Init(kCounter, label);
  set_timestamp0(micros);
}

void TimelineEvent::FlowBegin(const char* label, int64_t id, int64_t micros) {
  Init(kFlowBegin, label);
  set_timestamp0(micros);
  // Overload timestamp1_ with the flow ID.
  set_timestamp1_or_id(id);
}

void TimelineEvent::FlowStep(const char* label, int64_t id, int64_t micros) {
  Init(kFlowStep, label);
  set_timestamp0(micros);
  // Overload timestamp1_ with the flow ID.
  set_timestamp1_or_id(id);
}

void TimelineEvent::FlowEnd(const char* label, int64_t id, int64_t micros) {
  Init(kFlowEnd, label);
  set_timestamp0(micros);
  // Overload timestamp1_ with the flow ID.
  set_timestamp1_or_id(id);
}

void TimelineEvent::Metadata(const char* label, int64_t micros) {
  Init(kMetadata, label);
  set_timestamp0(micros);
}

void TimelineEvent::CompleteWithPreSerializedArgs(char* args_json) {
  set_pre_serialized_args(true);
  SetNumArguments(1);
  SetArgument(0, "Dart Arguments", args_json);
  Complete();
}

void TimelineEvent::FormatArgument(intptr_t i,
                                   const char* name,
                                   const char* fmt,
                                   ...) {
  va_list args;
  va_start(args, fmt);
  arguments_.FormatArgument(i, name, fmt, args);
  va_end(args);
}

void TimelineEvent::Complete() {
  TimelineEventRecorder* recorder = Timeline::recorder();
  recorder->CompleteEvent(this);
  // Paired with |RecorderSynchronizationLock::EnterLock()| in
  // |TimelineStream::StartEvent()|.
  RecorderSynchronizationLock::ExitLock();
}

void TimelineEvent::Init(EventType event_type, const char* label) {
  ASSERT(label != nullptr);
  state_ = 0;
  timestamp0_ = 0;
  timestamp1_or_id_ = 0;
  flow_id_count_ = 0;
  flow_ids_.reset();
  OSThread* os_thread = OSThread::Current();
  ASSERT(os_thread != nullptr);
  thread_ = os_thread->trace_id();
  auto thread = Thread::Current();
  auto isolate = thread != nullptr ? thread->isolate() : nullptr;
  auto isolate_group = thread != nullptr ? thread->isolate_group() : nullptr;
  isolate_id_ = (isolate != nullptr) ? isolate->main_port() : ILLEGAL_PORT;
  isolate_group_id_ = (isolate_group != nullptr) ? isolate_group->id() : 0;
  isolate_data_ =
      (isolate != nullptr) ? isolate->init_callback_data() : nullptr;
  isolate_group_data_ =
      (isolate_group != nullptr) ? isolate_group->embedder_data() : nullptr;
  label_ = label;
  arguments_.Free();
  set_event_type(event_type);
  set_pre_serialized_args(false);
  set_owns_label(false);
}

bool TimelineEvent::Within(int64_t time_origin_micros,
                           int64_t time_extent_micros) const {
  if ((time_origin_micros == -1) || (time_extent_micros == -1)) {
    // No time range specified.
    return true;
  }
  if (IsFinishedDuration()) {
    // Event is from e_t0 to e_t1.
    int64_t e_t0 = TimeOrigin();
    int64_t e_t1 = TimeEnd();
    ASSERT(e_t0 <= e_t1);
    // Range is from r_t0 to r_t1.
    int64_t r_t0 = time_origin_micros;
    int64_t r_t1 = time_origin_micros + time_extent_micros;
    ASSERT(r_t0 <= r_t1);
    return !((r_t1 < e_t0) || (e_t1 < r_t0));
  }
  int64_t delta = TimeOrigin() - time_origin_micros;
  return (delta >= 0) && (delta <= time_extent_micros);
}

#ifndef PRODUCT
void TimelineEvent::PrintJSON(JSONStream* stream) const {
  PrintJSON(stream->writer());
}
#endif

void TimelineEvent::PrintJSON(JSONWriter* writer) const {
  writer->OpenObject();
  int64_t pid = OS::ProcessId();
  int64_t tid = OSThread::ThreadIdToIntPtr(thread_);
  writer->PrintProperty("name", label_);
  writer->PrintProperty("cat", stream_ != nullptr ? stream_->name() : nullptr);
  writer->PrintProperty64("tid", tid);
  writer->PrintProperty64("pid", pid);
  writer->PrintProperty64("ts", TimeOrigin());
  switch (event_type()) {
    case kBegin: {
      writer->PrintProperty("ph", "B");
    } break;
    case kEnd: {
      writer->PrintProperty("ph", "E");
    } break;
    case kDuration: {
      writer->PrintProperty("ph", "X");
      writer->PrintProperty64("dur", TimeDuration());
    } break;
    case kInstant: {
      writer->PrintProperty("ph", "i");
      writer->PrintProperty("s", "p");
    } break;
    case kAsyncBegin: {
      writer->PrintProperty("ph", "b");
      writer->PrintfProperty("id", "%" Px64 "", Id());
    } break;
    case kAsyncInstant: {
      writer->PrintProperty("ph", "n");
      writer->PrintfProperty("id", "%" Px64 "", Id());
    } break;
    case kAsyncEnd: {
      writer->PrintProperty("ph", "e");
      writer->PrintfProperty("id", "%" Px64 "", Id());
    } break;
    case kCounter: {
      writer->PrintProperty("ph", "C");
    } break;
    case kFlowBegin: {
      writer->PrintProperty("ph", "s");
      writer->PrintfProperty("id", "%" Px64 "", Id());
    } break;
    case kFlowStep: {
      writer->PrintProperty("ph", "t");
      writer->PrintfProperty("id", "%" Px64 "", Id());
    } break;
    case kFlowEnd: {
      writer->PrintProperty("ph", "f");
      writer->PrintProperty("bp", "e");
      writer->PrintfProperty("id", "%" Px64 "", Id());
    } break;
    case kMetadata: {
      writer->PrintProperty("ph", "M");
    } break;
    default:
      UNIMPLEMENTED();
  }

  if (ArgsArePreSerialized()) {
    ASSERT(arguments_.length() == 1);
    writer->AppendSerializedObject("args", arguments_[0].value);
    if (HasIsolateId()) {
      writer->UncloseObject();
      writer->PrintfProperty("isolateId", ISOLATE_SERVICE_ID_FORMAT_STRING,
                             static_cast<int64_t>(isolate_id_));
      writer->CloseObject();
    }
    if (HasIsolateGroupId()) {
      writer->UncloseObject();
      writer->PrintfProperty("isolateGroupId",
                             ISOLATE_GROUP_SERVICE_ID_FORMAT_STRING,
                             isolate_group_id_);
      writer->CloseObject();
    } else {
      ASSERT(isolate_group_id_ == ILLEGAL_PORT);
    }
  } else {
    writer->OpenObject("args");
    for (intptr_t i = 0; i < arguments_.length(); i++) {
      const TimelineEventArgument& arg = arguments_[i];
      writer->PrintProperty(arg.name, arg.value);
    }
    if (HasIsolateId()) {
      writer->PrintfProperty("isolateId", ISOLATE_SERVICE_ID_FORMAT_STRING,
                             static_cast<int64_t>(isolate_id_));
    }
    if (HasIsolateGroupId()) {
      writer->PrintfProperty("isolateGroupId",
                             ISOLATE_GROUP_SERVICE_ID_FORMAT_STRING,
                             isolate_group_id_);
    } else {
      ASSERT(isolate_group_id_ == ILLEGAL_PORT);
    }
    writer->CloseObject();
  }
  writer->CloseObject();
}

#if defined(SUPPORT_PERFETTO) && !defined(PRODUCT)
namespace {

// Trait used to map 64-bit ids (e.g. isolate or isolate group id) to
// interned id of a corresponding string representation.
//
// This way we only need to generate formatted string once, instead of
// repeatedly formatting it and then interning resulting string to get an
// iid.
class IdToIidTrait {
 public:
  struct Pair {
    uint64_t id;
    uint64_t formatted_iid;
  };
  using Key = uint64_t;
  using Value = uint64_t;

  static Key KeyOf(const Pair& kv) { return kv.id; }
  static Value ValueOf(const Pair& kv) { return kv.formatted_iid; }
  static uword Hash(Key key) {
    return Utils::WordHash(static_cast<intptr_t>(key));
  }
  static bool IsKeyEqual(const Pair& kv, Key key) { return kv.id == key; }
};

using IdToIidMap = MallocDirectChainedHashMap<IdToIidTrait>;

class InternedDataBuilder : public ValueObject {
 private:
  using SequenceFlags = perfetto::protos::pbzero::TracePacket_SequenceFlags;

 public:
  // InternedData contains multiple independent interning dictionaries which
  // are used for different attributes.
#define PERFETTO_INTERNED_STRINGS_FIELDS_LIST(V)                               \
  V(event_categories, name)                                                    \
  V(event_names, name)                                                         \
  V(debug_annotation_names, name)                                              \
  V(debug_annotation_string_values, str)

  // Direct access for known strings.
#define PERFETTO_COMMON_INTERNED_STRINGS_LIST(V)                               \
  V(debug_annotation_names, isolateId)                                         \
  V(debug_annotation_names, isolateGroupId)

  InternedDataBuilder() = default;

  // Emit all strings added since the last invocation of |AttachInternedDataTo|
  // into |interned_data| of the given |TracePacket|.
  //
  // Mark the packet as depending on incremental state.
  void AttachInternedDataTo(perfetto::protos::pbzero::TracePacket* packet) {
    if (!AnyInternerHasNewlyInternedEntries()) {
      return;
    }

    packet->set_sequence_flags(sequence_flags_);
    // The first packet will have SEQ_INCREMENTAL_STATE_CLEARED
    // the rest will just have SEQ_NEEDS_INCREMENTAL_STATE.
    sequence_flags_ &= ~SequenceFlags::SEQ_INCREMENTAL_STATE_CLEARED;

    auto interned_data = packet->set_interned_data();

    // Flush individual interning dictionaries.
#define FLUSH_FIELD(name, proto_field)                                         \
  name##_.FlushNewlyInternedTo([interned_data](auto& iid, auto& str) {         \
    auto entry = interned_data->add_##name();                                  \
    entry->set_iid(iid);                                                       \
    entry->set_##proto_field(str);                                             \
  });

    PERFETTO_INTERNED_STRINGS_FIELDS_LIST(FLUSH_FIELD)
#undef FLUSH_FIELD
  }

#define DEFINE_GETTER(name, proto_field)                                       \
  perfetto_utils::StringInterner<Malloc>& name() { return name##_; }
  PERFETTO_INTERNED_STRINGS_FIELDS_LIST(DEFINE_GETTER)
#undef DEFINE_GETTER

#define DEFINE_GETTER_FOR_COMMON_STRING(category, str)                         \
  uint64_t iid_##str() {                                                       \
    if (iid_##str##_ == 0) {                                                   \
      iid_##str##_ = category().Intern(#str);                                  \
    }                                                                          \
    return iid_##str##_;                                                       \
  }

  PERFETTO_COMMON_INTERNED_STRINGS_LIST(DEFINE_GETTER_FOR_COMMON_STRING)

#undef DEFINE_GETTER_FOR_COMMON_STRING

  uint64_t InternFormattedIsolateId(uint64_t isolate_id) {
    return InternFormattedIdForDebugAnnotation(
        isolate_id_to_iid_of_formatted_string_,
        ISOLATE_SERVICE_ID_FORMAT_STRING, isolate_id);
  }

  uint64_t InternFormattedIsolateGroupId(uint64_t isolate_group_id) {
    return InternFormattedIdForDebugAnnotation(
        isolate_group_id_to_iid_of_formatted_string_,
        ISOLATE_GROUP_SERVICE_ID_FORMAT_STRING, isolate_group_id);
  }

 private:
  template <std::size_t kFormatLen>
  uint64_t InternFormattedIdForDebugAnnotation(IdToIidMap& cache,
                                               const char (&format)[kFormatLen],
                                               uint64_t id) {
    if (auto iid = cache.Lookup(id)) {
      return iid->formatted_iid;
    }

    // 20 characters is enough to format any uint64_t (or int64_t) value.
    char formatted[kFormatLen + 20];
    Utils::SNPrint(formatted, ARRAY_SIZE(formatted), format, id);

    auto formatted_iid = debug_annotation_string_values().Intern(formatted);
    cache.Insert({id, formatted_iid});
    return formatted_iid;
  }

  bool AnyInternerHasNewlyInternedEntries() const {
#define CHECK_FIELD(name, proto_field)                                         \
  if (name##_.HasNewlyInternedEntries()) return true;

    PERFETTO_INTERNED_STRINGS_FIELDS_LIST(CHECK_FIELD)
#undef CHECK_FIELD
    return false;
  }

  uint32_t sequence_flags_ = SequenceFlags::SEQ_INCREMENTAL_STATE_CLEARED |
                             SequenceFlags::SEQ_NEEDS_INCREMENTAL_STATE;

  // These are interned in debug_annotation_string_values space.
  IdToIidMap isolate_id_to_iid_of_formatted_string_;
  IdToIidMap isolate_group_id_to_iid_of_formatted_string_;

#define DEFINE_FIELD_FOR_COMMON_STRING(category, str) uint64_t iid_##str##_ = 0;

  PERFETTO_COMMON_INTERNED_STRINGS_LIST(DEFINE_FIELD_FOR_COMMON_STRING)

#undef DEFINE_FIELD_FOR_COMMON_STRING

#define DEFINE_FIELD(name, proto_field)                                        \
  perfetto_utils::StringInterner<Malloc> name##_;
  PERFETTO_INTERNED_STRINGS_FIELDS_LIST(DEFINE_FIELD)
#undef DEFINE_FIELD

  DISALLOW_COPY_AND_ASSIGN(InternedDataBuilder);
};

class TracePacketWriter : public ValueObject {
 public:
  using TracePacket = perfetto::protos::pbzero::TracePacket;
  using TrackEvent = perfetto::protos::pbzero::TrackEvent;

  using WriteCallback =
      std::function<void(protozero::HeapBuffered<TracePacket>&)>;

  TracePacketWriter(protozero::HeapBuffered<TracePacket>& packet,
                    WriteCallback&& write_callback,
                    bool intern_strings)
      : packet_(packet),
        write_callback_(std::move(write_callback)),
        intern_strings_(intern_strings) {}

  // Converting contents of the given |TimelineEvent| into one or more
  // Perfetto packets and write them out using |write_callback_| which
  // was specified when this writer was constructed.
  //
  // It uses scratch |packet_| which is reset after it is written out.
  void WriteEvent(const TimelineEvent& event) {
    if (!CanBeRepresented(event.event_type())) {
      return;
    }
    if (event.IsDuration()) {
      // Duration events must be converted to pairs of begin and end events to
      // be serialized in Perfetto's format.
      PopulateAndWritePacket(TimelineEvent::kBegin, event.TimeOrigin(), event);
      PopulateAndWritePacket(TimelineEvent::kEnd, event.TimeEnd(), event);
    } else {
      PopulateAndWritePacket(event.event_type(), event.TimeOrigin(), event);
    }
  }

 private:
  static TrackEvent::Type ToPerfettoType(TimelineEvent::EventType event_type) {
    switch (event_type) {
      case TimelineEvent::kAsyncBegin:
      case TimelineEvent::kBegin:
        return TrackEvent::Type::TYPE_SLICE_BEGIN;
      case TimelineEvent::kAsyncInstant:
      case TimelineEvent::kInstant:
        return TrackEvent::Type::TYPE_INSTANT;
      case TimelineEvent::kAsyncEnd:
      case TimelineEvent::kEnd:
        return TrackEvent::Type::TYPE_SLICE_END;
      default:
        return TrackEvent::Type::TYPE_UNSPECIFIED;
    }
  }

  static bool IsSync(TimelineEvent::EventType event_type) {
    switch (event_type) {
      case TimelineEvent::kBegin:
      case TimelineEvent::kInstant:
      case TimelineEvent::kEnd:
        return true;
      default:
        return false;
    }
  }

  static bool CanBeRepresented(TimelineEvent::EventType event_type) {
    return event_type == TimelineEvent::kDuration ||
           ToPerfettoType(event_type) != TrackEvent::Type::TYPE_UNSPECIFIED;
  }

  void PopulateAndWritePacket(TimelineEvent::EventType event_type,
                              int64_t timestamp,
                              const TimelineEvent& event) {
    PopulatePacket(event_type, timestamp, event);
    interned_data_builder_.AttachInternedDataTo(packet_.get());
    write_callback_(packet_);
    packet_.Reset();
  }

  void PopulatePacket(TimelineEvent::EventType event_type,
                      int64_t timestamp,
                      const TimelineEvent& event) {
    ASSERT(event_type == event.event_type() ||
           (event.IsDuration() && (event_type == TimelineEvent::kBegin ||
                                   event_type == TimelineEvent::kEnd)));
    perfetto_utils::SetTrustedPacketSequenceId(packet_.get());
    perfetto_utils::SetTimestampAndMonotonicClockId(packet_.get(), timestamp);

    TrackEvent* track_event = packet_->set_track_event();
    SetTrackEventCategory(track_event, event.stream()->name());

    track_event->set_track_uuid(IsSync(event_type)
                                    ? OSThread::ThreadIdToIntPtr(event.thread())
                                    : event.Id());
    const auto perfetto_type = ToPerfettoType(event_type);
    track_event->set_type(perfetto_type);
    if (perfetto_type != TrackEvent::Type::TYPE_SLICE_END) {
      SetTrackEventName(track_event, event.label());
      for (intptr_t i = 0; i < event.flow_id_count(); ++i) {
        // TODO(derekx): |TrackEvent|s have a |terminating_flow_ids| field that
        // we aren't able to populate right now because we aren't keeping track
        // of terminating flow IDs in |TimelineEvent|. I'm not even sure if
        // using that field will provide any benefit though.
        track_event->add_flow_ids(event.FlowIds()[i]);
      }
    }
    AddDebugAnnotations(track_event, event);
  }

  void AddDebugAnnotations(TrackEvent* track_event,
                           const TimelineEvent& event) {
    if (event.GetNumArguments() > 0) {
      if (event.ArgsArePreSerialized()) {
        ASSERT(event.GetNumArguments() == 1);
        perfetto::protos::pbzero::DebugAnnotation& debug_annotation =
            *track_event->add_debug_annotations();
        SetDebugAnnotationName(debug_annotation, event.arguments()[0].name);
        debug_annotation.set_legacy_json_value(event.arguments()[0].value);
      } else {
        for (intptr_t i = 0; i < event.GetNumArguments(); ++i) {
          perfetto::protos::pbzero::DebugAnnotation& debug_annotation =
              *track_event->add_debug_annotations();
          SetDebugAnnotationName(debug_annotation, event.arguments()[i].name);
          SetDebugAnnotationStringValue(debug_annotation,
                                        event.arguments()[i].value);
        }
      }
    }
    if (event.HasIsolateId()) {
      perfetto::protos::pbzero::DebugAnnotation& debug_annotation =
          *track_event->add_debug_annotations();
      SetDebugAnnotationName(debug_annotation, "isolateId", [this](auto name) {
        return interned_data_builder_.iid_isolateId();
      });
      SetDebugAnnotationStringValueFromFormattedId(
          debug_annotation, ISOLATE_SERVICE_ID_FORMAT_STRING,
          event.isolate_id(), [this](auto id) {
            return interned_data_builder_.InternFormattedIsolateId(id);
          });
    }
    if (event.HasIsolateGroupId()) {
      perfetto::protos::pbzero::DebugAnnotation& debug_annotation =
          *track_event->add_debug_annotations();
      SetDebugAnnotationName(
          debug_annotation, "isolateGroupId", [this](auto name) {
            return interned_data_builder_.iid_isolateGroupId();
          });
      SetDebugAnnotationStringValueFromFormattedId(
          debug_annotation, ISOLATE_GROUP_SERVICE_ID_FORMAT_STRING,
          event.isolate_group_id(), [this](auto id) {
            return interned_data_builder_.InternFormattedIsolateGroupId(id);
          });
    }
  }

  // Helpers for setting string valued properties on |TrackEvent| and
  // |DebugAnnotation|, these can use interning if |intern_strings_| is
  // |true|.

  void SetTrackEventCategory(TrackEvent* track_event, const char* value) {
    if (intern_strings_) {
      track_event->add_category_iids(
          interned_data_builder_.event_categories().Intern(value));
    } else {
      track_event->add_categories(value);
    }
  }

  void SetTrackEventName(TrackEvent* track_event, const char* value) {
    if (intern_strings_) {
      track_event->set_name_iid(
          interned_data_builder_.event_names().Intern(value));
    } else {
      track_event->set_name(value);
    }
  }

  template <typename F>
  void SetDebugAnnotationName(
      perfetto::protos::pbzero::DebugAnnotation& debug_annotation,
      const char* name,
      F&& intern) {
    if (intern_strings_) {
      debug_annotation.set_name_iid(intern(name));
    } else {
      debug_annotation.set_name(name);
    }
  }

  void SetDebugAnnotationName(
      perfetto::protos::pbzero::DebugAnnotation& debug_annotation,
      const char* name) {
    SetDebugAnnotationName(debug_annotation, name, [this](auto name) {
      return interned_data_builder_.debug_annotation_names().Intern(name);
    });
  }

  void SetDebugAnnotationStringValue(
      perfetto::protos::pbzero::DebugAnnotation& debug_annotation,
      const char* value) {
    if (intern_strings_) {
      debug_annotation.set_string_value_iid(
          interned_data_builder_.debug_annotation_string_values().Intern(
              value));
    } else {
      debug_annotation.set_string_value(value);
    }
  }

  template <std::size_t kFormatLen, typename F>
  void SetDebugAnnotationStringValueFromFormattedId(
      perfetto::protos::pbzero::DebugAnnotation& debug_annotation,
      const char (&format)[kFormatLen],
      uint64_t id,
      F&& intern_id) {
    if (intern_strings_) {
      debug_annotation.set_string_value_iid(intern_id(id));
    } else {
      // 20 characters is enough to format any uint64_t (or int64_t) value.
      char formatted[kFormatLen + 20];
      Utils::SNPrint(formatted, ARRAY_SIZE(formatted), format, id);
      debug_annotation.set_string_value(formatted);
    }
  }

  protozero::HeapBuffered<perfetto::protos::pbzero::TracePacket>& packet_;
  WriteCallback write_callback_;
  const bool intern_strings_;

  InternedDataBuilder interned_data_builder_;

  DISALLOW_COPY_AND_ASSIGN(TracePacketWriter);
};

}  // namespace
#endif  // defined(SUPPORT_PERFETTO) && !defined(PRODUCT)

int64_t TimelineEvent::LowTime() const {
  return timestamp0_;
}

int64_t TimelineEvent::HighTime() const {
  if (event_type() == kDuration) {
    return timestamp1_or_id_;
  } else {
    return timestamp0_;
  }
}

int64_t TimelineEvent::TimeDuration() const {
  ASSERT(event_type() == kDuration);
  if (timestamp1_or_id_ == 0) {
    // This duration is still open, use current time as end.
    return OS::GetCurrentMonotonicMicrosForTimeline() - timestamp0_;
  }
  return timestamp1_or_id_ - timestamp0_;
}

bool TimelineEvent::HasIsolateId() const {
  return isolate_id_ != ILLEGAL_ISOLATE_ID;
}

bool TimelineEvent::HasIsolateGroupId() const {
  return isolate_group_id_ != ILLEGAL_ISOLATE_GROUP_ID;
}

void TimelineEvent::ClearIsolateGroupId() {
  isolate_group_id_ = ILLEGAL_ISOLATE_GROUP_ID;
}

TimelineTrackMetadata::TimelineTrackMetadata(intptr_t pid,
                                             intptr_t tid,
                                             CStringUniquePtr&& track_name)
    : pid_(pid), tid_(tid), track_name_(std::move(track_name)) {}

void TimelineTrackMetadata::set_track_name(CStringUniquePtr&& track_name) {
  track_name_ = std::move(track_name);
}

#if !defined(PRODUCT)
void TimelineTrackMetadata::PrintJSON(const JSONArray& jsarr_events) const {
  JSONObject jsobj(&jsarr_events);
  jsobj.AddProperty("name", "thread_name");
  jsobj.AddProperty("ph", "M");
  jsobj.AddProperty("pid", pid());
  jsobj.AddProperty("tid", tid());
  {
    JSONObject jsobj_args(&jsobj, "args");
    jsobj_args.AddPropertyF("name", "%s (%" Pd ")", track_name(), tid());
    jsobj_args.AddProperty("mode", "basic");
  }
}

#if defined(SUPPORT_PERFETTO)
void TimelineTrackMetadata::PopulateTracePacket(
    perfetto::protos::pbzero::TracePacket* track_descriptor_packet) const {
  perfetto_utils::SetTrustedPacketSequenceId(track_descriptor_packet);

  perfetto::protos::pbzero::TrackDescriptor& track_descriptor =
      *track_descriptor_packet->set_track_descriptor();
  track_descriptor.set_parent_uuid(pid());
  track_descriptor.set_uuid(tid());

  perfetto::protos::pbzero::ThreadDescriptor& thread_descriptor =
      *track_descriptor.set_thread();
  thread_descriptor.set_pid(pid());
  thread_descriptor.set_tid(tid());
  thread_descriptor.set_thread_name(track_name());
}
#endif  // defined(SUPPORT_PERFETTO)
#endif  // !defined(PRODUCT)

AsyncTimelineTrackMetadata::AsyncTimelineTrackMetadata(intptr_t pid,
                                                       intptr_t async_id)
    : pid_(pid), async_id_(async_id) {}

#if defined(SUPPORT_PERFETTO) && !defined(PRODUCT)
void AsyncTimelineTrackMetadata::PopulateTracePacket(
    perfetto::protos::pbzero::TracePacket* track_descriptor_packet) const {
  perfetto_utils::SetTrustedPacketSequenceId(track_descriptor_packet);
  perfetto::protos::pbzero::TrackDescriptor& track_descriptor =
      *track_descriptor_packet->set_track_descriptor();
  track_descriptor.set_parent_uuid(pid());
  track_descriptor.set_uuid(async_id());
}
#endif  // defined(SUPPORT_PERFETTO) && !defined(PRODUCT)

TimelineStream::TimelineStream(const char* name,
                               const char* fuchsia_name,
                               bool has_static_labels,
                               bool enabled)
    : name_(name),
      fuchsia_name_(fuchsia_name),
#if defined(DART_HOST_OS_FUCHSIA)
      enabled_(static_cast<uintptr_t>(true))  // For generated code.
#else
      enabled_(static_cast<uintptr_t>(enabled))
#endif
{
#if defined(DART_HOST_OS_MACOS)
  macos_log_ = os_log_create("Dart", name);
  has_static_labels_ = has_static_labels;
#endif
}

TimelineEvent* TimelineStream::StartEvent() {
  // Paired with |RecorderSynchronizationLock::ExitLock()| in
  // |TimelineEvent::Complete()|.
  //
  // The lock must be held until the event is completed to avoid having the
  // memory backing the event being freed in the middle of processing the
  // event.
  RecorderSynchronizationLock::EnterLock();
  TimelineEventRecorder* recorder = Timeline::recorder();
  if (!enabled() || (recorder == nullptr) ||
      !RecorderSynchronizationLock::IsActive()) {
    RecorderSynchronizationLock::ExitLock();
    return nullptr;
  }
  ASSERT(name_ != nullptr);
  TimelineEvent* event = recorder->StartEvent();
  if (event == nullptr) {
    RecorderSynchronizationLock::ExitLock();
    return nullptr;
  }
  event->StreamInit(this);
  return event;
}

TimelineEventScope::TimelineEventScope(TimelineStream* stream,
                                       const char* label)
    : StackResource(static_cast<Thread*>(nullptr)),
      stream_(stream),
      label_(label),
      enabled_(false) {
  Init();
}

TimelineEventScope::TimelineEventScope(Thread* thread,
                                       TimelineStream* stream,
                                       const char* label)
    : StackResource(thread), stream_(stream), label_(label), enabled_(false) {
  Init();
}

TimelineEventScope::~TimelineEventScope() {}

void TimelineEventScope::Init() {
  ASSERT(enabled_ == false);
  ASSERT(label_ != nullptr);
  ASSERT(stream_ != nullptr);
  if (!stream_->enabled()) {
    // Stream is not enabled, do nothing.
    return;
  }
  enabled_ = true;
  Thread* thread = static_cast<Thread*>(this->thread());
  if (thread != nullptr) {
    id_ = thread->GetNextTaskId();
  } else {
    static RelaxedAtomic<int64_t> next_bootstrap_task_id = {0};
    id_ = next_bootstrap_task_id.fetch_add(1);
  }
}

void TimelineEventScope::SetNumArguments(intptr_t length) {
  if (!enabled()) {
    return;
  }
  arguments_.SetNumArguments(length);
}

// |name| must be a compile time constant. Takes ownership of |argumentp|.
void TimelineEventScope::SetArgument(intptr_t i,
                                     const char* name,
                                     char* argument) {
  if (!enabled()) {
    return;
  }
  arguments_.SetArgument(i, name, argument);
}

// |name| must be a compile time constant. Copies |argument|.
void TimelineEventScope::CopyArgument(intptr_t i,
                                      const char* name,
                                      const char* argument) {
  if (!enabled()) {
    return;
  }
  arguments_.CopyArgument(i, name, argument);
}

void TimelineEventScope::FormatArgument(intptr_t i,
                                        const char* name,
                                        const char* fmt,
                                        ...) {
  if (!enabled()) {
    return;
  }
  va_list args;
  va_start(args, fmt);
  arguments_.FormatArgument(i, name, fmt, args);
  va_end(args);
}

void TimelineEventScope::StealArguments(TimelineEvent* event) {
  if (event == nullptr) {
    return;
  }
  event->StealArguments(&arguments_);
}

TimelineBeginEndScope::TimelineBeginEndScope(TimelineStream* stream,
                                             const char* label)
    : TimelineEventScope(stream, label) {
  EmitBegin();
}

TimelineBeginEndScope::TimelineBeginEndScope(Thread* thread,
                                             TimelineStream* stream,
                                             const char* label)
    : TimelineEventScope(thread, stream, label) {
  EmitBegin();
}

TimelineBeginEndScope::~TimelineBeginEndScope() {
  EmitEnd();
}

void TimelineBeginEndScope::EmitBegin() {
  if (!ShouldEmitEvent()) {
    return;
  }
  TimelineEvent* event = stream()->StartEvent();
  if (event == nullptr) {
    // Stream is now disabled.
    set_enabled(false);
    return;
  }
  ASSERT(event != nullptr);
  // Emit a begin event.
  event->Begin(label(), id());
  event->Complete();
}

void TimelineBeginEndScope::EmitEnd() {
  if (!ShouldEmitEvent()) {
    return;
  }
  TimelineEvent* event = stream()->StartEvent();
  if (event == nullptr) {
    // Stream is now disabled.
    set_enabled(false);
    return;
  }
  ASSERT(event != nullptr);
  // Emit an end event.
  event->End(label(), id());
  StealArguments(event);
  event->Complete();
}

bool TimelineEventBlock::InUseLocked() const {
  ASSERT(Timeline::recorder()->lock_.IsOwnedByCurrentThread());
  return in_use_;
}

bool TimelineEventBlock::ContainsEventsThatCanBeSerializedLocked() const {
  ASSERT(Timeline::recorder()->lock_.IsOwnedByCurrentThread());
  // Check that the block is not in use and not empty. |!block->in_use()| must
  // be checked first because we are only holding |lock_|. Holding |lock_|
  // makes it safe to call |in_use()| on any block, but only makes it safe to
  // call |IsEmpty()| on blocks that are not in use.
  return !InUseLocked() && !IsEmpty();
}

TimelineEventFilter::TimelineEventFilter(int64_t time_origin_micros,
                                         int64_t time_extent_micros)
    : time_origin_micros_(time_origin_micros),
      time_extent_micros_(time_extent_micros) {
  ASSERT(time_origin_micros_ >= -1);
  ASSERT(time_extent_micros_ >= -1);
}

TimelineEventFilter::~TimelineEventFilter() {}

IsolateTimelineEventFilter::IsolateTimelineEventFilter(
    Dart_Port isolate_id,
    int64_t time_origin_micros,
    int64_t time_extent_micros)
    : TimelineEventFilter(time_origin_micros, time_extent_micros),
      isolate_id_(isolate_id) {}

TimelineEventRecorder::TimelineEventRecorder()
    : time_low_micros_(0),
      time_high_micros_(0),
      track_uuid_to_track_metadata_lock_(),
      track_uuid_to_track_metadata_(
          &SimpleHashMap::SamePointerValue,
          TimelineEventRecorder::kTrackUuidToTrackMetadataInitialCapacity),
      async_track_uuid_to_track_metadata_lock_(),
      async_track_uuid_to_track_metadata_(
          &SimpleHashMap::SamePointerValue,
          TimelineEventRecorder::kTrackUuidToTrackMetadataInitialCapacity) {}

TimelineEventRecorder::~TimelineEventRecorder() {
  // We do not need to lock the following section, because at this point
  // |RecorderSynchronizationLock| must have been put in a state that prevents
  // the metadata maps from being modified.
  for (SimpleHashMap::Entry* entry = track_uuid_to_track_metadata_.Start();
       entry != nullptr; entry = track_uuid_to_track_metadata_.Next(entry)) {
    TimelineTrackMetadata* value =
        static_cast<TimelineTrackMetadata*>(entry->value);
    delete value;
  }
  for (SimpleHashMap::Entry* entry =
           async_track_uuid_to_track_metadata_.Start();
       entry != nullptr;
       entry = async_track_uuid_to_track_metadata_.Next(entry)) {
    AsyncTimelineTrackMetadata* value =
        static_cast<AsyncTimelineTrackMetadata*>(entry->value);
    delete value;
  }
}

#ifndef PRODUCT
void TimelineEventRecorder::PrintJSONMeta(const JSONArray& jsarr_events) {
  MutexLocker ml(&track_uuid_to_track_metadata_lock_);
  for (SimpleHashMap::Entry* entry = track_uuid_to_track_metadata_.Start();
       entry != nullptr; entry = track_uuid_to_track_metadata_.Next(entry)) {
    TimelineTrackMetadata* value =
        static_cast<TimelineTrackMetadata*>(entry->value);
    value->PrintJSON(jsarr_events);
  }
}

#if defined(SUPPORT_PERFETTO)
void TimelineEventRecorder::PrintPerfettoMeta(
    JSONBase64String* jsonBase64String) {
  ASSERT(jsonBase64String != nullptr);

  perfetto_utils::PopulateClockSnapshotPacket(packet_.get());
  perfetto_utils::AppendPacketToJSONBase64String(jsonBase64String, &packet_);
  packet_.Reset();
  perfetto_utils::PopulateProcessDescriptorPacket(packet_.get());
  perfetto_utils::AppendPacketToJSONBase64String(jsonBase64String, &packet_);
  packet_.Reset();

  {
    MutexLocker ml(&async_track_uuid_to_track_metadata_lock_);
    for (SimpleHashMap::Entry* entry =
             async_track_uuid_to_track_metadata_.Start();
         entry != nullptr;
         entry = async_track_uuid_to_track_metadata_.Next(entry)) {
      AsyncTimelineTrackMetadata* value =
          static_cast<AsyncTimelineTrackMetadata*>(entry->value);
      value->PopulateTracePacket(packet_.get());
      perfetto_utils::AppendPacketToJSONBase64String(jsonBase64String,
                                                     &packet_);
      packet_.Reset();
    }
  }

  {
    MutexLocker ml(&track_uuid_to_track_metadata_lock_);
    for (SimpleHashMap::Entry* entry = track_uuid_to_track_metadata_.Start();
         entry != nullptr; entry = track_uuid_to_track_metadata_.Next(entry)) {
      TimelineTrackMetadata* value =
          static_cast<TimelineTrackMetadata*>(entry->value);
      value->PopulateTracePacket(packet_.get());
      perfetto_utils::AppendPacketToJSONBase64String(jsonBase64String,
                                                     &packet_);
      packet_.Reset();
    }
  }
}
#endif  // defined(SUPPORT_PERFETTO)
#endif  // !defined(PRODUCT)

TimelineEvent* TimelineEventRecorder::ThreadBlockStartEvent() {
  // Grab the current thread.
  OSThread* thread = OSThread::Current();
  ASSERT(thread != nullptr);
  // Acquire the recorder lock in case we need to call |GetNewBlockLocked|. We
  // acquire the lock here and not directly before calls to |GetNewBlockLocked|
  // due to locking order restrictions.
  Mutex& recorder_lock = lock_;
  recorder_lock.Lock();
  Mutex* thread_block_lock = thread->timeline_block_lock();
  ASSERT(thread_block_lock != nullptr);
  // We are accessing the thread's timeline block- so take the lock here.
  // This lock will be held until the call to |CompleteEvent| is made.
  thread_block_lock->Lock();
#if defined(DEBUG)
  Thread* T = Thread::Current();
  if (T != nullptr) {
    T->IncrementNoSafepointScopeDepth();
  }
#endif  // defined(DEBUG)

  TimelineEventBlock* thread_block = thread->TimelineBlockLocked();

  if ((thread_block != nullptr) && thread_block->IsFull()) {
    // Thread has a block and it is full:
    // 1) Mark it as finished.
    thread->SetTimelineBlockLocked(nullptr);
    FinishBlock(thread_block);
    // 2) Allocate a new block.
    // We release |thread_block_lock| before calling |GetNewBlockLocked| to
    // avoid TSAN warnings about lock order inversion.
    thread_block_lock->Unlock();
    thread_block = GetNewBlockLocked();
    thread_block_lock->Lock();
    thread->SetTimelineBlockLocked(thread_block);
  } else if (thread_block == nullptr) {
    // Thread has no block. Attempt to allocate one.
    // We release |thread_block_lock| before calling |GetNewBlockLocked| to
    // avoid TSAN warnings about lock order inversion.
    thread_block_lock->Unlock();
    thread_block = GetNewBlockLocked();
    thread_block_lock->Lock();
    thread->SetTimelineBlockLocked(thread_block);
  }
  recorder_lock.Unlock();
  if (thread_block != nullptr) {
    // NOTE: We are exiting this function with the thread's block lock held.
    ASSERT(!thread_block->IsFull());
    TimelineEvent* event = thread_block->StartEventLocked();
    return event;
  }
// Drop lock here as no event is being handed out.
#if defined(DEBUG)
  if (T != nullptr) {
    T->DecrementNoSafepointScopeDepth();
  }
#endif  // defined(DEBUG)
  thread_block_lock->Unlock();
  return nullptr;
}

void TimelineEventRecorder::ResetTimeTracking() {
  time_high_micros_ = 0;
  time_low_micros_ = kMaxInt64;
}

void TimelineEventRecorder::ReportTime(int64_t micros) {
  if (time_high_micros_ < micros) {
    time_high_micros_ = micros;
  }
  if (time_low_micros_ > micros) {
    time_low_micros_ = micros;
  }
}

int64_t TimelineEventRecorder::TimeOriginMicros() const {
  if (time_high_micros_ == 0) {
    return 0;
  }
  return time_low_micros_;
}

int64_t TimelineEventRecorder::TimeExtentMicros() const {
  if (time_high_micros_ == 0) {
    return 0;
  }
  return time_high_micros_ - time_low_micros_;
}

void TimelineEventRecorder::ThreadBlockCompleteEvent(TimelineEvent* event) {
  if (event == nullptr) {
    return;
  }
#if defined(SUPPORT_PERFETTO) && !defined(PRODUCT)
  // Async track metadata is only written in Perfetto traces, and Perfetto
  // traces cannot be written when SUPPORT_PERFETTO is not defined, or when
  // PRODUCT is defined.
  if (event->event_type() == TimelineEvent::kAsyncBegin ||
      event->event_type() == TimelineEvent::kAsyncInstant) {
    AddAsyncTrackMetadataBasedOnEvent(*event);
  }
#endif  // defined(SUPPORT_PERFETTO) && !defined(PRODUCT)
  // Grab the current thread.
  OSThread* thread = OSThread::Current();
  ASSERT(thread != nullptr);
  // Unlock the thread's block lock.
  Mutex* thread_block_lock = thread->timeline_block_lock();
  ASSERT(thread_block_lock != nullptr);
#if defined(DEBUG)
  Thread* T = Thread::Current();
  if (T != nullptr) {
    T->DecrementNoSafepointScopeDepth();
  }
#endif  // defined(DEBUG)
  thread_block_lock->Unlock();
}

#ifndef PRODUCT
void TimelineEventRecorder::WriteTo(const char* directory) {
  Dart_FileOpenCallback file_open = Dart::file_open_callback();
  Dart_FileWriteCallback file_write = Dart::file_write_callback();
  Dart_FileCloseCallback file_close = Dart::file_close_callback();
  if ((file_open == nullptr) || (file_write == nullptr) ||
      (file_close == nullptr)) {
    OS::PrintErr("warning: Could not access file callbacks.");
    return;
  }

  // Acquire the recorder's lock to prevent the reclaimed blocks from being
  // handed out again until the trace has been serialized.
  MutexLocker ml(&lock_);
  Timeline::ReclaimCachedBlocksFromThreads();

  intptr_t pid = OS::ProcessId();
  char* filename =
      OS::SCreate(nullptr, "%s/dart-timeline-%" Pd ".json", directory, pid);
  void* file = (*file_open)(filename, true);
  if (file == nullptr) {
    OS::PrintErr("warning: Failed to write timeline file: %s\n", filename);
    free(filename);
    return;
  }
  free(filename);

  JSONStream js;
  TimelineEventFilter filter;
  PrintTraceEvent(&js, &filter);
  // Steal output from JSONStream.
  char* output = nullptr;
  intptr_t output_length = 0;
  js.Steal(&output, &output_length);
  (*file_write)(output, output_length, file);
  // Free the stolen output.
  free(output);
  (*file_close)(file);

  return;
}
#endif

void TimelineEventRecorder::FinishBlock(TimelineEventBlock* block) {
  if (block != nullptr) {
    block->Finish();
  }
}

void TimelineEventRecorder::AddTrackMetadataBasedOnThread(
    const intptr_t process_id,
    const intptr_t trace_id,
    const char* thread_name) {
  ASSERT(FLAG_timeline_recorder != nullptr);
  if (strcmp("none", FLAG_timeline_recorder) == 0 ||
      strcmp("callback", FLAG_timeline_recorder) == 0 ||
      strcmp("systrace", FLAG_timeline_recorder) == 0 ||
      FLAG_systrace_timeline) {
    // There is no way to retrieve track metadata when a no-op, callback, or
    // systrace recorder is in use, so we don't need to update the map in these
    // cases.
    return;
  }
  MutexLocker ml(&track_uuid_to_track_metadata_lock_);

  void* key = reinterpret_cast<void*>(trace_id);
  const intptr_t hash = Utils::WordHash(trace_id);
  SimpleHashMap::Entry* entry =
      track_uuid_to_track_metadata_.Lookup(key, hash, true);
  if (entry->value == nullptr) {
    entry->value = new TimelineTrackMetadata(
        process_id, trace_id,
        CStringUniquePtr(
            Utils::StrDup(thread_name == nullptr ? "" : thread_name)));
  } else {
    TimelineTrackMetadata* value =
        static_cast<TimelineTrackMetadata*>(entry->value);
    ASSERT(process_id == value->pid());
    value->set_track_name(CStringUniquePtr(
        Utils::StrDup(thread_name == nullptr ? "" : thread_name)));
  }
}

#if !defined(PRODUCT)
void TimelineEventRecorder::AddAsyncTrackMetadataBasedOnEvent(
    const TimelineEvent& event) {
  ASSERT(FLAG_timeline_recorder != nullptr);
  if (strcmp("none", FLAG_timeline_recorder) == 0 ||
      strcmp("callback", FLAG_timeline_recorder) == 0 ||
      strcmp("systrace", FLAG_timeline_recorder) == 0 ||
      FLAG_systrace_timeline) {
    // There is no way to retrieve track metadata when a no-op, callback, or
    // systrace recorder is in use, so we don't need to update the map in
    // these cases.
    return;
  }
  MutexLocker ml(&async_track_uuid_to_track_metadata_lock_);

  void* key = reinterpret_cast<void*>(event.Id());
  const intptr_t hash = Utils::WordHash(event.Id());
  SimpleHashMap::Entry* entry =
      async_track_uuid_to_track_metadata_.Lookup(key, hash, true);
  if (entry->value == nullptr) {
    entry->value = new AsyncTimelineTrackMetadata(OS::ProcessId(), event.Id());
  }
}
#endif  // !defined(PRODUCT)

TimelineEventFixedBufferRecorder::TimelineEventFixedBufferRecorder(
    intptr_t capacity)
    : memory_(nullptr),
      blocks_(nullptr),
      capacity_(capacity),
      num_blocks_(0),
      block_cursor_(0) {
  // Capacity must be a multiple of TimelineEventBlock::kBlockSize
  ASSERT((capacity % TimelineEventBlock::kBlockSize) == 0);
  // Allocate blocks array.
  num_blocks_ = capacity / TimelineEventBlock::kBlockSize;

  intptr_t size = Utils::RoundUp(num_blocks_ * sizeof(TimelineEventBlock),
                                 VirtualMemory::PageSize());
  const bool executable = false;
  const bool compressed = false;
  memory_ =
      VirtualMemory::Allocate(size, executable, compressed, "dart-timeline");
  if (memory_ == nullptr) {
    OUT_OF_MEMORY();
  }
  blocks_ = reinterpret_cast<TimelineEventBlock*>(memory_->address());
}

TimelineEventFixedBufferRecorder::~TimelineEventFixedBufferRecorder() {
  // We do not need to acquire any locks, because at this point we must have
  // reclaimed all the blocks, and |RecorderSynchronizationLock| must have been
  // put in a state that prevents blocks from being given out.
  delete memory_;
}

intptr_t TimelineEventFixedBufferRecorder::Size() {
  return memory_->size();
}

#ifndef PRODUCT
void TimelineEventFixedBufferRecorder::ForEachNonEmptyBlock(
    std::function<void(const TimelineEventBlock&)>&& handle_block) {
  // Acquire the recorder's lock to prevent the reclaimed blocks from being
  // handed out again until the trace has been serialized.
  MutexLocker ml(&lock_);
  Timeline::ReclaimCachedBlocksFromThreads();
  ResetTimeTracking();
  intptr_t block_offset = FindOldestBlockIndexLocked();
  if (block_offset == -1) {
    // All blocks are in use or empty.
    return;
  }
  for (intptr_t block_idx = 0; block_idx < num_blocks_; block_idx++) {
    TimelineEventBlock* block =
        &blocks_[(block_idx + block_offset) % num_blocks_];
    if (!block->ContainsEventsThatCanBeSerializedLocked()) {
      continue;
    }
    handle_block(*block);
  }
}

void TimelineEventBufferedRecorder::PrintEventsCommon(
    const TimelineEventFilter& filter,
    std::function<void(const TimelineEvent&)>&& print_impl) {
  ForEachNonEmptyBlock(
      [this, &filter, print_impl = std::move(print_impl)](auto& block) {
        for (intptr_t event_idx = 0, length = block.length();
             event_idx < length; event_idx++) {
          auto event = block.At(event_idx);
          if (filter.IncludeEvent(event) &&
              event->Within(filter.time_origin_micros(),
                            filter.time_extent_micros())) {
            ReportTime(event->LowTime());
            ReportTime(event->HighTime());
            print_impl(*event);
          }
        }
      });
}

void TimelineEventBufferedRecorder::PrintJSONEvents(
    const JSONArray& events,
    const TimelineEventFilter& filter) {
  PrintEventsCommon(filter, [&events](const TimelineEvent& event) {
    events.AddValue(&event);
  });
}

#if defined(SUPPORT_PERFETTO)
void TimelineEventBufferedRecorder::PrintPerfettoEvents(
    JSONBase64String* jsonBase64String,
    const TimelineEventFilter& filter) {
  TracePacketWriter writer(
      packet(),
      [&jsonBase64String](auto& packet) {
        perfetto_utils::AppendPacketToJSONBase64String(jsonBase64String,
                                                       &packet);
      },
      FLAG_intern_strings_when_writing_perfetto_timeline);

  PrintEventsCommon(filter, [&writer](const TimelineEvent& event) {
    writer.WriteEvent(event);
  });
}
#endif  // defined(SUPPORT_PERFETTO)

void TimelineEventBufferedRecorder::PrintJSON(JSONStream* js,
                                              TimelineEventFilter* filter) {
  JSONObject topLevel(js);
  topLevel.AddProperty("type", "Timeline");
  {
    JSONArray events(&topLevel, "traceEvents");
    PrintJSONMeta(events);
    PrintJSONEvents(events, *filter);
  }
  topLevel.AddPropertyTimeMicros("timeOriginMicros", TimeOriginMicros());
  topLevel.AddPropertyTimeMicros("timeExtentMicros", TimeExtentMicros());
}

#if defined(SUPPORT_PERFETTO)
void TimelineEventBufferedRecorder::PrintPerfettoTimeline(
    JSONStream* js,
    const TimelineEventFilter& filter) {
  JSONObject jsobj_topLevel(js);
  jsobj_topLevel.AddProperty("type", "PerfettoTimeline");

  js->AppendSerializedObject("\"trace\":");
  {
    JSONBase64String jsonBase64String(js);
    PrintPerfettoMeta(&jsonBase64String);
    PrintPerfettoEvents(&jsonBase64String, filter);
  }

  jsobj_topLevel.AddPropertyTimeMicros("timeOriginMicros", TimeOriginMicros());
  jsobj_topLevel.AddPropertyTimeMicros("timeExtentMicros", TimeExtentMicros());
}
#endif  // defined(SUPPORT_PERFETTO)

void TimelineEventBufferedRecorder::PrintTraceEvent(
    JSONStream* js,
    TimelineEventFilter* filter) {
  JSONArray events(js);
  PrintJSONMeta(events);
  PrintJSONEvents(events, *filter);
}
#endif  // !defined(PRODUCT)

void TimelineEventFixedBufferRecorder::ClearLocked() {
  ASSERT(lock_.IsOwnedByCurrentThread());
  for (intptr_t i = 0; i < num_blocks_; i++) {
    TimelineEventBlock* block = &blocks_[i];
    block->Reset();
  }
}

intptr_t TimelineEventFixedBufferRecorder::FindOldestBlockIndexLocked() const {
  ASSERT(lock_.IsOwnedByCurrentThread());
  int64_t earliest_time = kMaxInt64;
  intptr_t earliest_index = -1;
  for (intptr_t block_idx = 0; block_idx < num_blocks_; block_idx++) {
    TimelineEventBlock* block = &blocks_[block_idx];
    if (!block->ContainsEventsThatCanBeSerializedLocked()) {
      // Skip in use and empty blocks.
      continue;
    }
    if (block->LowerTimeBound() < earliest_time) {
      earliest_time = block->LowerTimeBound();
      earliest_index = block_idx;
    }
  }
  return earliest_index;
}

TimelineEvent* TimelineEventFixedBufferRecorder::StartEvent() {
  return ThreadBlockStartEvent();
}

void TimelineEventFixedBufferRecorder::CompleteEvent(TimelineEvent* event) {
  if (event == nullptr) {
    return;
  }
  ThreadBlockCompleteEvent(event);
}

TimelineEventBlock* TimelineEventRingRecorder::GetNewBlockLocked() {
  ASSERT(lock_.IsOwnedByCurrentThread());
  if (block_cursor_ == num_blocks_) {
    block_cursor_ = 0;
  }
  TimelineEventBlock* block = &blocks_[block_cursor_++];
  if (block->current_owner_ != nullptr) {
    MutexLocker ml(block->current_owner_->timeline_block_lock());
    block->current_owner_->SetTimelineBlockLocked(nullptr);
    block->Reset();
    block->Open();
  } else {
    block->Reset();
    block->Open();
  }
  return block;
}

TimelineEventBlock* TimelineEventStartupRecorder::GetNewBlockLocked() {
  ASSERT(lock_.IsOwnedByCurrentThread());
  if (block_cursor_ == num_blocks_) {
    return nullptr;
  }
  TimelineEventBlock* block = &blocks_[block_cursor_++];
  block->Reset();
  block->Open();
  return block;
}

TimelineEventCallbackRecorder::TimelineEventCallbackRecorder() {}

TimelineEventCallbackRecorder::~TimelineEventCallbackRecorder() {}

#ifndef PRODUCT
void TimelineEventCallbackRecorder::PrintJSON(JSONStream* js,
                                              TimelineEventFilter* filter) {
  UNREACHABLE();
}

#if defined(SUPPORT_PERFETTO)
void TimelineEventCallbackRecorder::PrintPerfettoTimeline(
    JSONStream* js,
    const TimelineEventFilter& filter) {
  UNREACHABLE();
}
#endif  // defined(SUPPORT_PERFETTO)

void TimelineEventCallbackRecorder::PrintTraceEvent(
    JSONStream* js,
    TimelineEventFilter* filter) {
  JSONArray events(js);
}
#endif  // !defined(PRODUCT)

TimelineEvent* TimelineEventCallbackRecorder::StartEvent() {
  TimelineEvent* event = new TimelineEvent();
  return event;
}

void TimelineEventCallbackRecorder::CompleteEvent(TimelineEvent* event) {
  OnEvent(event);
  delete event;
}

void TimelineEventEmbedderCallbackRecorder::OnEvent(TimelineEvent* event) {
  Dart_TimelineRecorderCallback callback = Timeline::callback();
  if (callback == nullptr) {
    return;
  }

  Dart_TimelineRecorderEvent recorder_event;
  recorder_event.version = DART_TIMELINE_RECORDER_CURRENT_VERSION;
  switch (event->event_type()) {
    case TimelineEvent::kBegin:
      recorder_event.type = Dart_Timeline_Event_Begin;
      break;
    case TimelineEvent::kEnd:
      recorder_event.type = Dart_Timeline_Event_End;
      break;
    case TimelineEvent::kInstant:
      recorder_event.type = Dart_Timeline_Event_Instant;
      break;
    case TimelineEvent::kDuration:
      recorder_event.type = Dart_Timeline_Event_Duration;
      break;
    case TimelineEvent::kAsyncBegin:
      recorder_event.type = Dart_Timeline_Event_Async_Begin;
      break;
    case TimelineEvent::kAsyncEnd:
      recorder_event.type = Dart_Timeline_Event_Async_End;
      break;
    case TimelineEvent::kAsyncInstant:
      recorder_event.type = Dart_Timeline_Event_Async_Instant;
      break;
    case TimelineEvent::kCounter:
      recorder_event.type = Dart_Timeline_Event_Counter;
      break;
    case TimelineEvent::kFlowBegin:
      recorder_event.type = Dart_Timeline_Event_Flow_Begin;
      break;
    case TimelineEvent::kFlowStep:
      recorder_event.type = Dart_Timeline_Event_Flow_Step;
      break;
    case TimelineEvent::kFlowEnd:
      recorder_event.type = Dart_Timeline_Event_Flow_End;
      break;
    default:
      // Type not expressible as Dart_Timeline_Event_Type: drop event.
      return;
  }
  recorder_event.timestamp0 = event->timestamp0();
  recorder_event.timestamp1_or_id = event->timestamp1_or_id();
  recorder_event.isolate = event->isolate_id();
  recorder_event.isolate_group = event->isolate_group_id();
  recorder_event.isolate_data = event->isolate_data();
  recorder_event.isolate_group_data = event->isolate_group_data();
  recorder_event.label = event->label();
  recorder_event.stream = event->stream()->name();
  recorder_event.argument_count = event->GetNumArguments();
  recorder_event.arguments =
      reinterpret_cast<Dart_TimelineRecorderEvent_Argument*>(
          event->arguments());

  NoActiveIsolateScope no_active_isolate_scope;
  callback(&recorder_event);
}

void TimelineEventNopRecorder::OnEvent(TimelineEvent* event) {
  // Do nothing.
}

TimelineEventPlatformRecorder::TimelineEventPlatformRecorder() {}

TimelineEventPlatformRecorder::~TimelineEventPlatformRecorder() {}

#ifndef PRODUCT
void TimelineEventPlatformRecorder::PrintJSON(JSONStream* js,
                                              TimelineEventFilter* filter) {
  UNREACHABLE();
}

#if defined(SUPPORT_PERFETTO)
void TimelineEventPlatformRecorder::PrintPerfettoTimeline(
    JSONStream* js,
    const TimelineEventFilter& filter) {
  UNREACHABLE();
}
#endif  // defined(SUPPORT_PERFETTO)

void TimelineEventPlatformRecorder::PrintTraceEvent(
    JSONStream* js,
    TimelineEventFilter* filter) {
  JSONArray events(js);
}
#endif  // !defined(PRODUCT)

TimelineEvent* TimelineEventPlatformRecorder::StartEvent() {
  TimelineEvent* event = new TimelineEvent();
  return event;
}

void TimelineEventPlatformRecorder::CompleteEvent(TimelineEvent* event) {
  OnEvent(event);
  delete event;
}

static void TimelineEventFileRecorderBaseStart(uword parameter) {
  reinterpret_cast<TimelineEventFileRecorderBase*>(parameter)->Drain();
}

TimelineEventFileRecorderBase::TimelineEventFileRecorderBase(const char* path)
    : TimelineEventRecorder() {
  Dart_FileOpenCallback file_open = Dart::file_open_callback();
  Dart_FileWriteCallback file_write = Dart::file_write_callback();
  Dart_FileCloseCallback file_close = Dart::file_close_callback();
  if ((file_open == nullptr) || (file_write == nullptr) ||
      (file_close == nullptr)) {
    OS::PrintErr("warning: Could not access file callbacks.");
    return;
  }
  void* file = (*file_open)(path, true);
  if (file == nullptr) {
    OS::PrintErr("warning: Failed to open timeline file: %s\n", path);
    return;
  }

  file_ = file;
}

TimelineEventFileRecorderBase::~TimelineEventFileRecorderBase() {
  // WARNING: |ShutDown()| must be called in the derived class destructor. This
  // work cannot be performed in this destructor, because then |DrainImpl()|
  // might run between when the derived class destructor completes, and when
  // |shutting_down_| is set to true, causing possible use-after-free errors.
  ASSERT(shutting_down_);

  if (file_ == nullptr) return;

  ASSERT(thread_id_ != OSThread::kInvalidThreadJoinId);
  OSThread::Join(thread_id_);
  thread_id_ = OSThread::kInvalidThreadJoinId;

  // At this point all blocks created by this recorder should be drained
  // and placed into |empty_blocks_|. Delete all of them.
  ASSERT(drained_);
  ASSERT(completed_blocks_head_ == nullptr);
  ASSERT(completed_blocks_tail_ == nullptr);
  while (empty_blocks_ != nullptr) {
    auto block = empty_blocks_;
    empty_blocks_ = empty_blocks_->next();
    delete block;
    block_count_--;
  }
  ASSERT(block_count_ == 0);

  FlushBuffer();

  Dart_FileCloseCallback file_close = Dart::file_close_callback();
  (*file_close)(file_);
  file_ = nullptr;
}

void TimelineEventFileRecorderBase::Drain() {
  MonitorLocker ml(&monitor_);
  thread_id_ = OSThread::GetCurrentThreadJoinId(OSThread::Current());
  ml.Notify();
  for (;;) {
    if (completed_blocks_head_ == nullptr) {
      ASSERT(completed_blocks_tail_ == nullptr);
      if (shutting_down_) {
        break;
      }
      ml.Wait();
      continue;  // Recheck empty.
    }
    // Take the whole list of pending blocks and drain all of them.
    auto blocks = completed_blocks_head_;
    completed_blocks_tail_ = completed_blocks_head_ = nullptr;
    {
      MonitorLeaveScope leave_ml(&ml);
      DrainBlockChain(blocks);
    }
  }
  drained_ = true;
  ml.Notify();
}

void TimelineEventFileRecorderBase::DrainBlockChain(TimelineEventBlock* block) {
  while (block != nullptr) {
    auto next_block = block->next();
    block->set_next(nullptr);

    for (intptr_t i = 0, length = block->length(); i < length; i++) {
      DrainImpl(*block->At(i));
    }
    block->Reset();

    // Place block for reuse.
    {
      MonitorLocker ml(&monitor_);
      block->set_next(empty_blocks_);
      empty_blocks_ = block;
    }
    block = next_block;
  }
}

void TimelineEventFileRecorderBase::FlushBuffer() {
  if (buffer_pos_ != 0) {
    WriteToFile(buffer_.get(), buffer_pos_);
    buffer_pos_ = 0;
  }
}

void TimelineEventFileRecorderBase::Write(const char* bytes, intptr_t length) {
  if (length >= kBufferSize / 2) {
    FlushBuffer();
    WriteToFile(bytes, length);
    return;
  }

  do {
    intptr_t space_left = kBufferSize - buffer_pos_;
    intptr_t bytes_to_write = Utils::Minimum(length, space_left);
    memcpy(buffer_.get() + buffer_pos_, bytes, bytes_to_write);  // NOLINT
    buffer_pos_ += bytes_to_write;
    length -= bytes_to_write;
    bytes += bytes_to_write;
    if (buffer_pos_ == kBufferSize) {
      FlushBuffer();
    }
  } while (length > 0);
}

void TimelineEventFileRecorderBase::WriteToFile(const char* buffer,
                                                intptr_t len) const {
  Dart_FileWriteCallback file_write = Dart::file_write_callback();
  (*file_write)(buffer, len, file_);
}

TimelineEvent* TimelineEventFileRecorderBase::StartEvent() {
  return ThreadBlockStartEvent();
}

void TimelineEventFileRecorderBase::CompleteEvent(TimelineEvent* event) {
  if (event == nullptr) {
    return;
  }
  if (file_ == nullptr) {
    delete event;
    return;
  }
  ThreadBlockCompleteEvent(event);
}

void TimelineEventFileRecorderBase::FinishBlock(TimelineEventBlock* block) {
  TimelineEventRecorder::FinishBlock(block);

  if (block != nullptr) {
    // Append completed block to the end of the list of completed blocks.
    // We want to keep events from the same thread ordered in sequentially
    // in the output.
    MonitorLocker ml(&monitor_);
    block->set_next(nullptr);
    if (completed_blocks_tail_ != nullptr) {
      completed_blocks_tail_->set_next(block);
      completed_blocks_tail_ = block;
    } else {
      completed_blocks_head_ = completed_blocks_tail_ = block;
    }
    ml.Notify();
  }
}

void TimelineEventFileRecorderBase::StartUp(const char* name) {
  OSThread::Start(name, TimelineEventFileRecorderBaseStart,
                  reinterpret_cast<uword>(this));

  MonitorLocker ml(&monitor_);
  while (thread_id_ == OSThread::kInvalidThreadJoinId) {
    ml.Wait();
  }
}

// Must be called in derived class destructors.
// See |~TimelineEventFileRecorderBase()| for an explanation.
void TimelineEventFileRecorderBase::ShutDown() {
  MonitorLocker ml(&monitor_);
  shutting_down_ = true;
  ml.NotifyAll();
  while (!drained_) {
    ml.Wait();
  }
}

TimelineEventBlock* TimelineEventFileRecorderBase::GetNewBlockLocked() {
  ASSERT(lock_.IsOwnedByCurrentThread());
  // Start by reusing a block.
  TimelineEventBlock* block = nullptr;
  if (empty_blocks_ != nullptr) {
    // TODO(vegorov) maybe we don't want to take a lock just to grab an empty
    // block?
    MonitorLocker ml(&monitor_);
    if (empty_blocks_ != nullptr) {
      block = empty_blocks_;
      empty_blocks_ = empty_blocks_->next();
      if (FLAG_trace_timeline) {
        OS::PrintErr("Reused empty block %p\n", block);
      }
    }
  }
  if (block == nullptr) {
    block = new TimelineEventBlock(block_count_++);
    if (FLAG_trace_timeline) {
      OS::PrintErr("Created new block %p\n", block);
    }
  }
  block->Open();

  return block;
}

void TimelineEventFileRecorderBase::ClearLocked() {
  ASSERT(lock_.IsOwnedByCurrentThread());
}

TimelineEventFileRecorder::TimelineEventFileRecorder(const char* path)
    : TimelineEventFileRecorderBase(path), first_(true) {
  // Chrome trace format has two forms:
  //   Object form:  { "traceEvents": [ event, event, event ] }
  //   Array form:   [ event, event, event ]
  // For this recorder, we use the array form because Catapult will handle a
  // missing ending bracket in this form in case we don't cleanly end the
  // trace.
  Write("[\n");
  StartUp("TimelineEventFileRecorder");
}

TimelineEventFileRecorder::~TimelineEventFileRecorder() {
  ShutDown();
  Write("]\n");
}

void TimelineEventFileRecorder::AddTrackMetadataBasedOnThread(
    const intptr_t process_id,
    const intptr_t trace_id,
    const char* thread_name) {
  TimelineEvent* event = StartEvent();
  event->Metadata("thread_name");
  event->SetNumArguments(1);
  event->CopyArgument(0, "name", thread_name);
  CompleteEvent(event);
}

void TimelineEventFileRecorder::DrainImpl(const TimelineEvent& event) {
  JSONWriter writer;
  if (first_) {
    first_ = false;
  } else {
    writer.buffer()->AddChar(',');
  }
  event.PrintJSON(&writer);
  char* output = nullptr;
  intptr_t output_length = 0;
  writer.Steal(&output, &output_length);
  Write(output, output_length);
  free(output);
}

#if defined(SUPPORT_PERFETTO) && !defined(PRODUCT)
class TimelineEventPerfettoFileRecorder : public TimelineEventFileRecorderBase {
 public:
  explicit TimelineEventPerfettoFileRecorder(const char* path);
  virtual ~TimelineEventPerfettoFileRecorder();

  const char* name() const final { return PERFETTO_FILE_RECORDER_NAME; }

 private:
  void WritePacket(
      protozero::HeapBuffered<perfetto::protos::pbzero::TracePacket>* packet);
  void DrainImpl(const TimelineEvent& event) final;

  TracePacketWriter writer_;
};

static TimelineEventRecorder* CreateTimelineEventPerfettoFileRecorder(
    const char* filename) {
  return new TimelineEventPerfettoFileRecorder(filename);
}

TimelineEventPerfettoFileRecorder::TimelineEventPerfettoFileRecorder(
    const char* path)
    : TimelineEventFileRecorderBase(path),
      writer_(
          packet(),
          [this](auto& packet) { this->WritePacket(&packet); },
          FLAG_intern_strings_when_writing_perfetto_timeline) {
  protozero::HeapBuffered<perfetto::protos::pbzero::TracePacket>& packet =
      this->packet();

  perfetto_utils::PopulateClockSnapshotPacket(packet.get());
  WritePacket(&packet);
  packet.Reset();

  perfetto_utils::PopulateProcessDescriptorPacket(packet.get());
  WritePacket(&packet);
  packet.Reset();

  StartUp("TimelineEventPerfettoFileRecorder");
}

TimelineEventPerfettoFileRecorder::~TimelineEventPerfettoFileRecorder() {
  ShutDown();

  protozero::HeapBuffered<perfetto::protos::pbzero::TracePacket>& packet =
      this->packet();
  // We do not need to lock the following section, because at this point
  // |RecorderSynchronizationLock| must have been put in a state that prevents
  // the metadata maps from being modified.
  for (SimpleHashMap::Entry* entry = track_uuid_to_track_metadata().Start();
       entry != nullptr; entry = track_uuid_to_track_metadata().Next(entry)) {
    TimelineTrackMetadata* value =
        static_cast<TimelineTrackMetadata*>(entry->value);
    value->PopulateTracePacket(packet.get());
    WritePacket(&packet);
    packet.Reset();
  }
  for (SimpleHashMap::Entry* entry =
           async_track_uuid_to_track_metadata().Start();
       entry != nullptr;
       entry = async_track_uuid_to_track_metadata().Next(entry)) {
    AsyncTimelineTrackMetadata* value =
        static_cast<AsyncTimelineTrackMetadata*>(entry->value);
    value->PopulateTracePacket(packet.get());
    WritePacket(&packet);
    packet.Reset();
  }
}

void TimelineEventPerfettoFileRecorder::WritePacket(
    protozero::HeapBuffered<perfetto::protos::pbzero::TracePacket>* packet) {
  const std::tuple<std::unique_ptr<const uint8_t[]>, intptr_t>& response =
      perfetto_utils::GetProtoPreamble(packet);
  Write(reinterpret_cast<const char*>(std::get<0>(response).get()),
        std::get<1>(response));
  for (const protozero::ScatteredHeapBuffer::Slice& slice :
       packet->GetSlices()) {
    Write(reinterpret_cast<const char*>(slice.start()),
          slice.size() - slice.unused_bytes());
  }
}

void TimelineEventPerfettoFileRecorder::DrainImpl(const TimelineEvent& event) {
  writer_.WriteEvent(event);
  if (event.event_type() == TimelineEvent::kAsyncBegin ||
      event.event_type() == TimelineEvent::kAsyncInstant) {
    AddAsyncTrackMetadataBasedOnEvent(event);
  }
}
#endif  // defined(SUPPORT_PERFETTO) && !defined(PRODUCT)

TimelineEventEndlessRecorder::TimelineEventEndlessRecorder()
    : head_(nullptr), tail_(nullptr), block_index_(0) {}

TimelineEventEndlessRecorder::~TimelineEventEndlessRecorder() {
  ASSERT(head_ == nullptr);
}

#ifndef PRODUCT
void TimelineEventEndlessRecorder::ForEachNonEmptyBlock(
    std::function<void(const TimelineEventBlock&)>&& handle_block) {
  // Acquire the recorder's lock to prevent the reclaimed blocks from being
  // handed out again until the trace has been serialized.
  MutexLocker ml(&lock_);
  Timeline::ReclaimCachedBlocksFromThreads();
  ResetTimeTracking();
  for (TimelineEventBlock* current = head_; current != nullptr;
       current = current->next()) {
    if (!current->ContainsEventsThatCanBeSerializedLocked()) {
      continue;
    }
    handle_block(*current);
  }
}
#endif  // !defined(PRODUCT)

TimelineEvent* TimelineEventEndlessRecorder::StartEvent() {
  return ThreadBlockStartEvent();
}

void TimelineEventEndlessRecorder::CompleteEvent(TimelineEvent* event) {
  if (event == nullptr) {
    return;
  }
  ThreadBlockCompleteEvent(event);
}

TimelineEventBlock* TimelineEventEndlessRecorder::GetNewBlockLocked() {
  ASSERT(lock_.IsOwnedByCurrentThread());
  TimelineEventBlock* block = new TimelineEventBlock(block_index_++);
  block->Open();
  if (head_ == nullptr) {
    head_ = tail_ = block;
  } else {
    tail_->set_next(block);
    tail_ = block;
  }
  if (FLAG_trace_timeline) {
    OS::PrintErr("Created new block %p\n", block);
  }
  return block;
}

void TimelineEventEndlessRecorder::ClearLocked() {
  ASSERT(lock_.IsOwnedByCurrentThread());
  TimelineEventBlock* current = head_;
  while (current != nullptr) {
    TimelineEventBlock* next = current->next();
    delete current;
    current = next;
  }
  head_ = nullptr;
  tail_ = nullptr;
  block_index_ = 0;
}

TimelineEventBlock::TimelineEventBlock(intptr_t block_index)
    : next_(nullptr),
      length_(0),
      block_index_(block_index),
      current_owner_(nullptr),
      in_use_(false) {}

TimelineEventBlock::~TimelineEventBlock() {
  Reset();
}

#ifndef PRODUCT
void TimelineEventBlock::PrintJSON(JSONStream* js) const {
  ASSERT(!InUseLocked());
  JSONArray events(js);
  for (intptr_t i = 0; i < length(); i++) {
    const TimelineEvent* event = At(i);
    if (event->IsValid()) {
      events.AddValue(event);
    }
  }
}
#endif

TimelineEvent* TimelineEventBlock::StartEventLocked() {
  OSThread* os_thread = OSThread::Current();
  ASSERT(os_thread != nullptr);
  ASSERT(os_thread == current_owner_);
  ASSERT(os_thread->timeline_block_lock()->IsOwnedByCurrentThread());
  ASSERT(!IsFull());
  if (FLAG_trace_timeline) {
    intptr_t tid = OSThread::ThreadIdToIntPtr(os_thread->id());
    OS::PrintErr("StartEvent in block %p for thread %" Pd "\n", this, tid);
  }
  return &events_[length_++];
}

int64_t TimelineEventBlock::LowerTimeBound() const {
  if (length_ == 0) {
    return kMaxInt64;
  }
  ASSERT(length_ > 0);
  return events_[0].TimeOrigin();
}

void TimelineEventBlock::Reset() {
  for (intptr_t i = 0; i < kBlockSize; i++) {
    // Clear any extra data.
    events_[i].Reset();
  }
  length_ = 0;
  current_owner_ = nullptr;
  in_use_ = false;
}

void TimelineEventBlock::Open() {
  OSThread* os_thread = OSThread::Current();
  ASSERT(os_thread != nullptr);
  current_owner_ = os_thread;
  in_use_ = true;
}

void TimelineEventBlock::Finish() {
  if (FLAG_trace_timeline) {
    OS::PrintErr("Finish block %p\n", this);
  }
  current_owner_ = nullptr;
  in_use_ = false;
#ifndef PRODUCT
  if (Service::timeline_stream.enabled()) {
    ServiceEvent service_event(ServiceEvent::kTimelineEvents);
    service_event.set_timeline_event_block(this);
    Service::HandleEvent(&service_event, /* enter_safepoint */ false);
  }
#endif
}

void DartTimelineEventHelpers::ReportTaskEvent(
    TimelineEvent* event,
    int64_t id,
    intptr_t flow_id_count,
    std::unique_ptr<const int64_t[]>& flow_ids,
    intptr_t type,
    char* name,
    char* args) {
  const int64_t start = OS::GetCurrentMonotonicMicrosForTimeline();
  switch (static_cast<TimelineEvent::EventType>(type)) {
    case TimelineEvent::kAsyncInstant:
      event->AsyncInstant(name, id, start);
      break;
    case TimelineEvent::kAsyncBegin:
      event->AsyncBegin(name, id, start);
      break;
    case TimelineEvent::kAsyncEnd:
      event->AsyncEnd(name, id, start);
      break;
    case TimelineEvent::kBegin:
      event->Begin(name, id, start);
      break;
    case TimelineEvent::kEnd:
      event->End(name, id, start);
      break;
    case TimelineEvent::kFlowBegin:
      event->FlowBegin(name, id, start);
      break;
    case TimelineEvent::kFlowStep:
      event->FlowStep(name, id, start);
      break;
    case TimelineEvent::kFlowEnd:
      event->FlowEnd(name, id, start);
      break;
    case TimelineEvent::kInstant:
      event->Instant(name, start);
      break;
    default:
      UNREACHABLE();
  }
  if (flow_id_count > 0) {
    ASSERT(type == TimelineEvent::kBegin || type == TimelineEvent::kInstant ||
           type == TimelineEvent::kAsyncBegin ||
           type == TimelineEvent::kAsyncInstant);

    event->SetFlowIds(flow_id_count, flow_ids);
  }
  event->set_owns_label(true);
  event->CompleteWithPreSerializedArgs(args);
}

}  // namespace dart

#endif  // defined(SUPPORT_TIMELINE)
