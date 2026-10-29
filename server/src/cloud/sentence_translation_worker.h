#pragma once

#include "cloud/sentence_translation.h"

#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>
#include <thread>

namespace SentenceTranslation
{
struct RequestOwner
{
    std::uint64_t clientId = 0;
    std::uint64_t focusEpoch = 0;
    std::uint64_t requestId = 0;
};

// One in-flight request plus the latest pending request. The callback runs on
// this worker thread; consumers must marshal it to their owning thread and
// re-check the target and request there before editing any application text.
// Stop/destruction must run on the owning thread, never inside the callback.
class Worker
{
  public:
    using Translate = std::function<Result(const std::string &)>;
    using Complete = std::function<void(const RequestOwner &, Result)>;

    Worker(Translate translate, Complete complete);
    ~Worker();
    Worker(const Worker &) = delete;
    Worker &operator=(const Worker &) = delete;

    bool Submit(RequestOwner owner, std::string source);
    void Cancel();
    void Stop();

  private:
    struct Job
    {
        RequestOwner owner;
        std::uint64_t generation;
        std::string source;
    };
    void Run();

    Translate translate_;
    Complete complete_;
    std::mutex mutex_;
    std::condition_variable changed_;
    std::optional<Job> pending_;
    std::uint64_t generation_ = 0;
    bool stopping_ = false;
    std::thread thread_;
};
} // namespace SentenceTranslation
