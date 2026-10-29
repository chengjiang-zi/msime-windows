#pragma once

#include <cstdint>
#include <string>

namespace FanyNamedPipe
{
void StartSentenceTranslation();
void StopSentenceTranslation();
void SubmitSentenceTranslation(std::uint64_t clientId, std::uint64_t focusEpoch, std::uint64_t requestId,
                               const std::wstring &source);
} // namespace FanyNamedPipe
