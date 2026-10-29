#include "cloud/sentence_translation_worker.h"

#include <utility>

namespace SentenceTranslation
{
Worker::Worker(Translate translate, Complete complete)
    : translate_(std::move(translate)), complete_(std::move(complete)), thread_(&Worker::Run, this)
{
}

Worker::~Worker()
{
    Stop();
}

bool Worker::Submit(RequestOwner owner, std::string source)
{
    if (!owner.clientId || !owner.focusEpoch || !owner.requestId || !detail::IsValidSource(source))
        return false;
    {
        std::lock_guard lock(mutex_);
        if (stopping_)
            return false;
        pending_ = Job{owner, ++generation_, std::move(source)};
    }
    changed_.notify_one();
    return true;
}

void Worker::Cancel()
{
    std::lock_guard lock(mutex_);
    ++generation_;
    pending_.reset();
}

void Worker::Stop()
{
    {
        std::lock_guard lock(mutex_);
        if (stopping_)
            return;
        stopping_ = true;
        ++generation_;
        pending_.reset();
    }
    changed_.notify_one();
    if (thread_.joinable())
        thread_.join();
}

void Worker::Run()
{
    for (;;)
    {
        std::unique_lock lock(mutex_);
        changed_.wait(lock, [&] { return stopping_ || pending_.has_value(); });
        if (stopping_)
            return;
        Job job = std::move(*pending_);
        pending_.reset();
        lock.unlock();

        Result result{Status::ProviderUnavailable, {}};
        try
        {
            if (translate_)
                result = translate_(job.source);
        }
        catch (...)
        {
            result = {Status::TranslationFailed, {}};
        }

        lock.lock();
        const bool current = !stopping_ && job.generation == generation_;
        lock.unlock();
        if (current && complete_)
        {
            try
            {
                complete_(job.owner, std::move(result));
            }
            catch (...)
            {
                // A callback must never terminate the worker or expose text.
            }
        }
    }
}
} // namespace SentenceTranslation
