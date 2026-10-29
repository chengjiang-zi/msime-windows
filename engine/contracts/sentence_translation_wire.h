#pragma once

#include "ipc_protocol_limits.h"

#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace FanyImeSentenceTranslation
{
enum class Status : unsigned
{
    Success = 0,
    InvalidInput = 1,
    ProviderUnavailable = 2,
    TranslationFailed = 3,
};

struct Reply
{
    std::uint64_t requestId = 0;
    Status status = Status::TranslationFailed;
    std::wstring text;
};

// The worker pipe carries fixed UTF-16 frames. On overflow report failure;
// never silently truncate a translation before it replaces the source text.
inline std::wstring EncodeReply(std::uint64_t requestId, Status status, const std::wstring &text)
{
    if (!requestId || static_cast<unsigned>(status) > static_cast<unsigned>(Status::TranslationFailed))
        return {};
    const std::wstring prefix = std::to_wstring(requestId) + L"|";
    if (status == Status::Success && (text.empty() || text.find(L'\0') != std::wstring::npos ||
                                      prefix.size() + 2 + text.size() > FanyImePipeLimits::CandidateTextMaxLength))
        status = Status::TranslationFailed;
    return prefix + static_cast<wchar_t>(L'0' + static_cast<unsigned>(status)) + L"|" +
           (status == Status::Success ? text : std::wstring{});
}

inline std::optional<Reply> DecodeReply(std::wstring_view payload)
{
    if (payload.empty() || payload.size() > FanyImePipeLimits::CandidateTextMaxLength)
        return std::nullopt;
    const auto separator = payload.find(L'|');
    if (separator == std::wstring_view::npos || separator == 0 || separator > 20 || separator + 2 >= payload.size() ||
        payload[separator + 2] != L'|' || payload[separator + 1] < L'0' || payload[separator + 1] > L'3')
        return std::nullopt;
    std::uint64_t id = 0;
    for (std::size_t i = 0; i < separator; ++i)
    {
        if (payload[i] < L'0' || payload[i] > L'9')
            return std::nullopt;
        const auto digit = static_cast<unsigned>(payload[i] - L'0');
        if (id > ((std::numeric_limits<std::uint64_t>::max)() - digit) / 10)
            return std::nullopt;
        id = id * 10 + digit;
    }
    if (!id)
        return std::nullopt;
    const auto status = static_cast<Status>(payload[separator + 1] - L'0');
    std::wstring text(payload.substr(separator + 3));
    if ((status == Status::Success && text.empty()) || (status != Status::Success && !text.empty()) ||
        text.find(L'\0') != std::wstring::npos)
        return std::nullopt;
    return Reply{id, status, std::move(text)};
}
} // namespace FanyImeSentenceTranslation
