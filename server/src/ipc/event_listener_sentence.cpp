#include "ipc/event_listener_sentence.h"

#include "cloud/sentence_translation.h"
#include "cloud/sentence_translation_worker.h"
#include "engine/contracts/sentence_translation_wire.h"
#include "ipc/ipc.h"
#include "utils/common_utils.h"

#include <memory>
#include <mutex>
#include <utility>

namespace FanyNamedPipe
{
namespace
{
std::mutex g_sentenceMutex;
std::shared_ptr<SentenceTranslation::Worker> g_sentenceWorker;

void Reply(const SentenceTranslation::RequestOwner &owner, SentenceTranslation::Result result)
{
    if (!IsActivePipeClient(owner.clientId, owner.focusEpoch) || !PipeClientOwnsForegroundInput(owner.clientId) ||
        !ClientNegotiatedSentenceTranslation(owner.clientId))
        return;
    auto status = static_cast<FanyImeSentenceTranslation::Status>(result.status);
    std::wstring translated;
    try
    {
        if (result.status == SentenceTranslation::Status::Success)
            translated = string_to_wstring(result.text);
    }
    catch (...)
    {
        status = FanyImeSentenceTranslation::Status::TranslationFailed;
    }
    const auto payload = FanyImeSentenceTranslation::EncodeReply(owner.requestId, status, translated);
    if (!payload.empty())
        SendToTsfWorkerThreadClientViaNamedpipe(owner.clientId, owner.focusEpoch,
                                                FanyImeWorkerReplyType::SentenceTranslationResult, payload);
}
} // namespace

void StartSentenceTranslation()
{
    std::lock_guard lock(g_sentenceMutex);
    if (!g_sentenceWorker)
        g_sentenceWorker =
            std::make_shared<SentenceTranslation::Worker>(SentenceTranslation::TranslateEnglishToChinese, Reply);
}

void StopSentenceTranslation()
{
    std::shared_ptr<SentenceTranslation::Worker> worker;
    {
        std::lock_guard lock(g_sentenceMutex);
        worker = std::move(g_sentenceWorker);
    }
    if (worker)
        worker->Stop();
}

void SubmitSentenceTranslation(std::uint64_t clientId, std::uint64_t focusEpoch, std::uint64_t requestId,
                               const std::wstring &source)
{
    const SentenceTranslation::RequestOwner owner{clientId, focusEpoch, requestId};
    std::shared_ptr<SentenceTranslation::Worker> worker;
    {
        std::lock_guard lock(g_sentenceMutex);
        worker = g_sentenceWorker;
    }
    try
    {
        if (worker && worker->Submit(owner, wstring_to_string(source)))
            return;
    }
    catch (...)
    {
        // Never log source text or provider details.
    }
    Reply(owner, {SentenceTranslation::Status::InvalidInput, {}});
}
} // namespace FanyNamedPipe
