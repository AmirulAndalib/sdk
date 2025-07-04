// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <utility>

#include "vm/message_handler.h"

#include "vm/dart.h"
#include "vm/heap/safepoint.h"
#include "vm/isolate.h"
#include "vm/lockers.h"
#include "vm/object.h"
#include "vm/object_store.h"
#include "vm/os.h"
#include "vm/port.h"
#include "vm/thread_interrupter.h"

namespace dart {

DECLARE_FLAG(bool, trace_service_pause_events);

class MessageHandlerTask : public ThreadPool::Task {
 public:
  explicit MessageHandlerTask(MessageHandler* handler) : handler_(handler) {
    ASSERT(handler != nullptr);
  }

  virtual void Run() {
    ASSERT(handler_ != nullptr);
    handler_->TaskCallback();
  }

 private:
  MessageHandler* handler_;

  DISALLOW_COPY_AND_ASSIGN(MessageHandlerTask);
};

// static
const char* MessageHandler::MessageStatusString(MessageStatus status) {
  switch (status) {
    case kOK:
      return "OK";
    case kError:
      return "Error";
    case kShutdown:
      return "Shutdown";
    default:
      UNREACHABLE();
      return "Illegal";
  }
}

MessageHandler::MessageHandler()
    : queue_(new MessageQueue()),
      oob_queue_(new MessageQueue()),
      oob_message_handling_allowed_(true),
      paused_for_messages_(false),
      paused_(0),
#if !defined(PRODUCT)
      should_pause_on_start_(false),
      should_pause_on_exit_(false),
      is_paused_on_start_(false),
      is_paused_on_exit_(false),
      remembered_paused_on_exit_status_(kOK),
      paused_timestamp_(-1),
#endif
      task_running_(false),
      pool_(nullptr),
      start_callback_(nullptr),
      end_callback_(nullptr),
      callback_data_(0) {
  ASSERT(queue_ != nullptr);
  ASSERT(oob_queue_ != nullptr);
}

MessageHandler::~MessageHandler() {
  delete queue_;
  delete oob_queue_;
  queue_ = nullptr;
  oob_queue_ = nullptr;
  pool_ = nullptr;
}

const char* MessageHandler::name() const {
  return "<unnamed>";
}

void MessageHandler::MessageNotify(Message::Priority priority) {
  // By default, there is no custom message notification.
}

bool MessageHandler::Run(ThreadPool* pool,
                         StartCallback start_callback,
                         EndCallback end_callback,
                         CallbackData data) {
  MonitorLocker ml(&monitor_);
  if (FLAG_trace_isolates) {
    OS::PrintErr(
        "[+] Starting message handler:\n"
        "\thandler:    %s\n",
        name());
  }
  ASSERT(pool_ == nullptr);
  pool_ = pool;
  start_callback_ = start_callback;
  end_callback_ = end_callback;
  callback_data_ = data;
  task_running_ = true;
  bool result = pool_->Run<MessageHandlerTask>(this);
  if (!result) {
    pool_ = nullptr;
    start_callback_ = nullptr;
    end_callback_ = nullptr;
    callback_data_ = 0;
    task_running_ = false;
  }
  return result;
}

void MessageHandler::PostMessage(std::unique_ptr<Message> message,
                                 bool before_events) {
  Message::Priority saved_priority;

  {
    MonitorLocker ml(&monitor_);
    if (FLAG_trace_isolates) {
      Isolate* source_isolate = Isolate::Current();
      if (source_isolate != nullptr) {
        OS::PrintErr(
            "[>] Posting message:\n"
            "\tlen:        %" Pd "\n\tsource:     (%" Pd64
            ") %s\n\tdest:       %s\n"
            "\tdest_port:  %" Pd64 "\n",
            message->Size(), static_cast<int64_t>(source_isolate->main_port()),
            source_isolate->name(), name(), message->dest_port());
      } else {
        OS::PrintErr(
            "[>] Posting message:\n"
            "\tlen:        %" Pd
            "\n\tsource:     <native code>\n"
            "\tdest:       %s\n"
            "\tdest_port:  %" Pd64 "\n",
            message->Size(), name(), message->dest_port());
      }
    }

    saved_priority = message->priority();
    if (message->IsOOB()) {
      oob_queue_->Enqueue(std::move(message), before_events);
    } else {
      queue_->Enqueue(std::move(message), before_events);
    }
    if (paused_for_messages_) {
      ml.Notify();
    }

    if (pool_ != nullptr && !task_running_) {
      task_running_ = true;
      const bool launched_successfully = pool_->Run<MessageHandlerTask>(this);
      ASSERT(launched_successfully);
    }
  }

  // Invoke any custom message notification.
  MessageNotify(saved_priority);
}

std::unique_ptr<Message> MessageHandler::DequeueMessage(
    Message::Priority min_priority) {
  ASSERT(monitor_.IsOwnedByCurrentThread());
  std::unique_ptr<Message> message = oob_queue_->Dequeue();
  if ((message == nullptr) && (min_priority < Message::kOOBPriority)) {
    message = queue_->Dequeue();
  }
  return message;
}

void MessageHandler::ClearOOBQueue() {
  oob_queue_->Clear();
}

MessageHandler::MessageStatus MessageHandler::HandleMessages(
    MonitorLocker* ml,
    bool allow_normal_messages,
    bool allow_multiple_normal_messages) {
  ASSERT(monitor_.IsOwnedByCurrentThread());

  // Scheduling of the mutator thread during the isolate start can cause this
  // thread to safepoint.
  // We want to avoid holding the message handler monitor during the safepoint
  // operation to avoid possible deadlocks, which can occur if other threads are
  // sending messages to this message handler.
  //
  // If isolate() returns nullptr [StartIsolateScope] does nothing.
  ml->Exit();
  StartIsolateScope start_isolate(isolate());
  ml->Enter();

  auto idle_time_handler =
      isolate() != nullptr ? isolate()->group()->idle_time_handler() : nullptr;

  MessageStatus max_status = kOK;
  Message::Priority min_priority =
      ((allow_normal_messages && !paused()) ? Message::kNormalPriority
                                            : Message::kOOBPriority);
  std::unique_ptr<Message> message = DequeueMessage(min_priority);
  while (message != nullptr) {
    intptr_t message_len = message->Size();
    if (FLAG_trace_isolates) {
      OS::PrintErr(
          "[<] Handling message:\n"
          "\tlen:        %" Pd
          "\n"
          "\thandler:    %s\n"
          "\tport:       %" Pd64 "\n",
          message_len, name(), message->dest_port());
    }

    // Release the monitor_ temporarily while we handle the message.
    // The monitor was acquired in MessageHandler::TaskCallback().
    ml->Exit();
    Message::Priority saved_priority = message->priority();
    Dart_Port saved_dest_port = message->dest_port();
    MessageStatus status = kOK;
    {
      DisableIdleTimerScope disable_idle_timer(idle_time_handler);
      status = HandleMessage(std::move(message));
    }
    if (status > max_status) {
      max_status = status;
    }
    ml->Enter();
    if (FLAG_trace_isolates) {
      OS::PrintErr(
          "[.] Message handled (%s):\n"
          "\tlen:        %" Pd
          "\n"
          "\thandler:    %s\n"
          "\tport:       %" Pd64 "\n",
          MessageStatusString(status), message_len, name(), saved_dest_port);
    }
    // If we are shutting down, do not process any more messages.
    if (status == kShutdown) {
      ClearOOBQueue();
      break;
    }

    // Remember time since the last message. Don't consider OOB messages so
    // interacting with the VM service doesn't trigger additional idle tasks.
    if ((FLAG_idle_timeout_micros != 0) &&
        (saved_priority == Message::kNormalPriority)) {
      if (idle_time_handler != nullptr) {
        idle_time_handler->UpdateStartIdleTime();
      }
    }

    // Some callers want to process only one normal message and then quit. At
    // the same time it is OK to process multiple OOB messages.
    if ((saved_priority == Message::kNormalPriority) &&
        !allow_multiple_normal_messages) {
      // We processed one normal message.  Allow no more.
      allow_normal_messages = false;
    }

    // Reevaluate the minimum allowable priority.  The paused state
    // may have changed as part of handling the message.  We may also
    // have encountered an error during message processing.
    //
    // Even if we encounter an error, we still process pending OOB
    // messages so that we don't lose the message notification.
    min_priority = (((max_status == kOK) && allow_normal_messages && !paused())
                        ? Message::kNormalPriority
                        : Message::kOOBPriority);
    message = DequeueMessage(min_priority);
  }
  return max_status;
}

MessageHandler::MessageStatus MessageHandler::HandleNextMessage() {
  // We can only call HandleNextMessage when this handler is not
  // assigned to a thread pool.
  MonitorLocker ml(&monitor_);
  ASSERT(pool_ == nullptr);
#if defined(DEBUG)
  CheckAccess();
#endif
  return HandleMessages(&ml, true, false);
}

MessageHandler::MessageStatus MessageHandler::PauseAndHandleAllMessages(
    int64_t timeout_millis) {
  MonitorLocker ml(&monitor_, /*no_safepoint_scope=*/false);
  ASSERT(task_running_);
#if defined(DEBUG)
  CheckAccess();
#endif
  paused_for_messages_ = true;
  while (queue_->IsEmpty() && oob_queue_->IsEmpty()) {
    Monitor::WaitResult wr;
    {
      // Ensure this thread is at a safepoint while we wait for new messages to
      // arrive.
      TransitionVMToNative transition(Thread::Current());
      wr = ml.Wait(timeout_millis);
    }
    ASSERT(task_running_);
    if (wr == Monitor::kTimedOut) {
      break;
    }
    if (queue_->IsEmpty()) {
      // There are only OOB messages. Handle them and then continue waiting for
      // normal messages unless there is an error.
      MessageStatus status = HandleMessages(&ml, false, false);
      if (status != kOK) {
        paused_for_messages_ = false;
        return status;
      }
    }
  }
  paused_for_messages_ = false;
  return HandleMessages(&ml, true, true);
}

MessageHandler::MessageStatus MessageHandler::HandleOOBMessages() {
  if (!oob_message_handling_allowed_) {
    return kOK;
  }
  MonitorLocker ml(&monitor_);
#if defined(DEBUG)
  CheckAccess();
#endif
  return HandleMessages(&ml, false, false);
}

#if !defined(PRODUCT)
bool MessageHandler::ShouldPauseOnStart(MessageStatus status) const {
  Isolate* owning_isolate = isolate();
  if (owning_isolate == nullptr) {
    return false;
  }
  // If we are restarting or shutting down, we do not want to honor
  // should_pause_on_start or should_pause_on_exit.
  return (status != MessageHandler::kShutdown) && should_pause_on_start() &&
         owning_isolate->is_runnable();
}

bool MessageHandler::ShouldPauseOnExit(MessageStatus status) const {
  Isolate* owning_isolate = isolate();
  if (owning_isolate == nullptr) {
    return false;
  }
  return (status != MessageHandler::kShutdown) && should_pause_on_exit() &&
         owning_isolate->is_runnable();
}
#endif

bool MessageHandler::HasOOBMessages() {
  MonitorLocker ml(&monitor_);
  return !oob_queue_->IsEmpty();
}

#if defined(TESTING)
std::unique_ptr<Message> MessageHandler::StealOOBMessage() {
  MonitorLocker ml(&monitor_);
  ASSERT(!oob_queue_->IsEmpty());
  return oob_queue_->Dequeue();
}
#endif

bool MessageHandler::HasMessages() {
  MonitorLocker ml(&monitor_);
  return !queue_->IsEmpty();
}

void MessageHandler::TaskCallback() {
  ASSERT(Isolate::Current() == nullptr);
  MessageStatus status = kOK;
  bool run_end_callback = false;
  EndCallback end_callback = nullptr;
  CallbackData callback_data = 0;
  {
    // We will occasionally release and reacquire this monitor in this
    // function. Whenever we reacquire the monitor we *must* process
    // all pending OOB messages, or we may miss a request for vm
    // shutdown.
    MonitorLocker ml(&monitor_);

    // This method is running on the message handler task. Which means no
    // other message handler tasks will be started until this one sets
    // [task_running_] to false.
    ASSERT(task_running_);

#if !defined(PRODUCT)
    if (ShouldPauseOnStart(kOK)) {
      if (!is_paused_on_start()) {
        PausedOnStartLocked(&ml, true);
      }
      // More messages may have come in before we (re)acquired the monitor.
      status = HandleMessages(&ml, false, false);
      if (ShouldPauseOnStart(status)) {
        // Still paused.
        ASSERT(oob_queue_->IsEmpty());
        task_running_ = false;  // No task in queue.
        return;
      } else {
        PausedOnStartLocked(&ml, false);
      }
    }
    if (is_paused_on_exit()) {
      status = HandleMessages(&ml, false, false);
      if (ShouldPauseOnExit(status)) {
        // Still paused.
        ASSERT(oob_queue_->IsEmpty());
        task_running_ = false;  // No task in queue.
        return;
      } else {
        PausedOnExitLocked(&ml, false);
        if (status != kShutdown) {
          status = remembered_paused_on_exit_status_;
        }
      }
    }
#endif  // !defined(PRODUCT)

    if (status == kOK) {
      if (start_callback_ != nullptr) {
        // Initialize the message handler by running its start function,
        // if we have one.  For an isolate, this will run the isolate's
        // main() function.
        //
        // Release the monitor_ temporarily while we call the start callback.
        ml.Exit();
        status = start_callback_(callback_data_);
        ASSERT(Isolate::Current() == nullptr);
        start_callback_ = nullptr;
        ml.Enter();
      }

      // Handle any pending messages for this message handler.
      if (status != kShutdown) {
        status = HandleMessages(&ml, (status == kOK), true);
      }
    }

    // The isolate exits when it encounters an error or when it no
    // longer has live ports.
    if (status != kOK || !KeepAliveLocked()) {
#if !defined(PRODUCT)
      if (ShouldPauseOnExit(status)) {
        if (FLAG_trace_service_pause_events) {
          OS::PrintErr(
              "Isolate %s paused before exiting. "
              "Use Dart DevTools to release it.\n",
              name());
        }
        remembered_paused_on_exit_status_ = status;
        PausedOnExitLocked(&ml, true);
        // More messages may have come in while we released the monitor.
        status = HandleMessages(&ml, /*allow_normal_messages=*/false,
                                /*allow_multiple_normal_messages=*/false);
        if (ShouldPauseOnExit(status)) {
          // Still paused.
          ASSERT(oob_queue_->IsEmpty());
          task_running_ = false;  // No task in queue.
          return;
        } else {
          PausedOnExitLocked(&ml, false);
        }
      }
#endif  // !defined(PRODUCT)
      if (FLAG_trace_isolates) {
        if (status != kOK && thread() != nullptr) {
          const Error& error = Error::Handle(thread()->sticky_error());
          OS::PrintErr(
              "[-] Stopping message handler (%s):\n"
              "\thandler:    %s\n"
              "\terror:    %s\n",
              MessageStatusString(status), name(), error.ToCString());
        } else {
          OS::PrintErr(
              "[-] Stopping message handler (%s):\n"
              "\thandler:    %s\n",
              MessageStatusString(status), name());
        }
      }
      pool_ = nullptr;
      // Decide if we have a callback before releasing the monitor.
      end_callback = end_callback_;
      callback_data = callback_data_;
      run_end_callback = end_callback_ != nullptr;
    }

    // Clear task_running_ last.  This allows other tasks to potentially start
    // for this message handler.
    ASSERT(oob_queue_->IsEmpty());
    task_running_ = false;
  }

  // The handler may have been deleted by another thread here if it is a native
  // message handler.

  if (run_end_callback) {
    ASSERT(end_callback != nullptr);
    end_callback(callback_data);
    // The handler may have been deleted after this point.
  }
}

void MessageHandler::OnPortClosed(Dart_Port port) {
  if (FLAG_trace_isolates) {
    MonitorLocker ml(&monitor_);
    OS::PrintErr(
        "[-] Closing port:\n"
        "\thandler:    %s\n"
        "\tport:       %" Pd64 "\n",
        name(), port);
  }
}

void MessageHandler::OnAllPortsClosed() {
  MonitorLocker ml(&monitor_);
  if (FLAG_trace_isolates) {
    OS::PrintErr(
        "[-] Closing all ports:\n"
        "\thandler:    %s\n",
        name());
  }
  queue_->Clear();
  oob_queue_->Clear();
}

#if !defined(PRODUCT)
void MessageHandler::DebugDump() {
  PortMap::DebugDumpForMessageHandler(this);
}

void MessageHandler::PausedOnStart(bool paused) {
  MonitorLocker ml(&monitor_);
  PausedOnStartLocked(&ml, paused);
}

void MessageHandler::PausedOnStartLocked(MonitorLocker* ml, bool paused) {
  if (paused) {
    ASSERT(!is_paused_on_start_);
    ASSERT(paused_timestamp_ == -1);
    paused_timestamp_ = OS::GetCurrentTimeMillis();
    // Temporarily release the monitor when calling out to
    // NotifyPauseOnStart.  This avoids a dead lock that can occur
    // when this message handler tries to post a message while a
    // message is being posted to it.
    ml->Exit();
    NotifyPauseOnStart();
    ml->Enter();
    is_paused_on_start_ = true;
  } else {
    ASSERT(is_paused_on_start_);
    ASSERT(paused_timestamp_ != -1);
    paused_timestamp_ = -1;
    // Resumed. Clear the resume request of the owning isolate.
    Isolate* owning_isolate = isolate();
    if (owning_isolate != nullptr) {
      owning_isolate->GetAndClearResumeRequest();
    }
    is_paused_on_start_ = false;
  }
}

void MessageHandler::PausedOnExit(bool paused) {
  MonitorLocker ml(&monitor_);
  PausedOnExitLocked(&ml, paused);
}

void MessageHandler::PausedOnExitLocked(MonitorLocker* ml, bool paused) {
  if (paused) {
    ASSERT(!is_paused_on_exit_);
    ASSERT(paused_timestamp_ == -1);
    paused_timestamp_ = OS::GetCurrentTimeMillis();
    // Temporarily release the monitor when calling out to
    // NotifyPauseOnExit.  This avoids a dead lock that can
    // occur when this message handler tries to post a message
    // while a message is being posted to it.
    ml->Exit();
    NotifyPauseOnExit();
    ml->Enter();
    is_paused_on_exit_ = true;
  } else {
    ASSERT(is_paused_on_exit_);
    ASSERT(paused_timestamp_ != -1);
    paused_timestamp_ = -1;
    // Resumed. Clear the resume request of the owning isolate.
    Isolate* owning_isolate = isolate();
    if (owning_isolate != nullptr) {
      owning_isolate->GetAndClearResumeRequest();
    }
    is_paused_on_exit_ = false;
  }
}
#endif  // !defined(PRODUCT)

MessageHandler::AcquiredQueues::AcquiredQueues(MessageHandler* handler)
    : handler_(handler), ml_(&handler->monitor_) {
  ASSERT(handler != nullptr);
  handler_->oob_message_handling_allowed_ = false;
}

MessageHandler::AcquiredQueues::~AcquiredQueues() {
  ASSERT(handler_ != nullptr);
  handler_->oob_message_handling_allowed_ = true;
}

}  // namespace dart
