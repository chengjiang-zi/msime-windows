#include "cloud/sentence_translation_worker.h"
#include "tests/includes/test_framework.h"

#include <chrono>
#include <future>

namespace
{
using namespace std::chrono_literals;
struct ReleaseOnExit
{
    std::promise<void> &gate;
    bool released = false;
    void Release()
    {
        if (!released)
        {
            released = true;
            gate.set_value();
        }
    }
    ~ReleaseOnExit()
    {
        Release();
    }
};
} // namespace

TEST_CASE(sentence_worker_discards_superseded_result_and_delivers_latest_request)
{
    using namespace SentenceTranslation;
    std::promise<void> started;
    std::promise<void> gate;
    auto ready = gate.get_future().share();
    std::promise<RequestOwner> completed;
    auto completion = completed.get_future();
    Worker worker(
        [&](const std::string &source) {
            if (source == "first")
            {
                started.set_value();
                ready.wait();
            }
            return Result{Status::Success, "ok"};
        },
        [&](const RequestOwner &owner, Result result) {
            if (result.status == Status::Success)
                completed.set_value(owner);
        });
    ReleaseOnExit release{gate};
    REQUIRE(!worker.Submit({}, "ignored"));
    REQUIRE(worker.Submit({1, 2, 3}, "first"));
    REQUIRE(started.get_future().wait_for(3s) == std::future_status::ready);
    REQUIRE(worker.Submit({1, 2, 4}, "second"));
    release.Release();
    REQUIRE(completion.wait_for(3s) == std::future_status::ready);
    REQUIRE_EQ(completion.get().requestId, std::uint64_t{4});
    worker.Stop();
}

TEST_CASE(sentence_worker_cancel_drops_delayed_result)
{
    using namespace SentenceTranslation;
    std::promise<void> started;
    std::promise<void> gate;
    auto ready = gate.get_future().share();
    std::promise<void> completed;
    auto completion = completed.get_future();
    Worker worker(
        [&](const std::string &) {
            started.set_value();
            ready.wait();
            return Result{Status::Success, "ok"};
        },
        [&](const RequestOwner &, Result) { completed.set_value(); });
    ReleaseOnExit release{gate};
    REQUIRE(worker.Submit({1, 2, 3}, "hello"));
    REQUIRE(started.get_future().wait_for(3s) == std::future_status::ready);
    worker.Cancel();
    release.Release();
    worker.Stop();
    REQUIRE(completion.wait_for(0ms) == std::future_status::timeout);
}
