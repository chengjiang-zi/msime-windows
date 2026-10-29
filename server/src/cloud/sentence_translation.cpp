#include "cloud/sentence_translation.h"

#include <utf8.h>
#include <algorithm>
#include <cctype>

namespace SentenceTranslation::detail
{
namespace
{
constexpr size_t kMaxSourceBytes = 4096;
constexpr size_t kMaxSourceCharacters = 1000;
constexpr size_t kMaxResultBytes = 8192;

bool HasNonWhitespace(const std::string &text)
{
    return std::any_of(text.begin(), text.end(), [](unsigned char ch) { return !std::isspace(ch); });
}
} // namespace

bool IsValidSource(const std::string &source)
{
    return !source.empty() && source.size() <= kMaxSourceBytes && source.find('\0') == std::string::npos &&
           HasNonWhitespace(source) && utf8::is_valid(source.begin(), source.end()) &&
           static_cast<size_t>(utf8::distance(source.begin(), source.end())) <= kMaxSourceCharacters;
}

Result TranslateWith(const std::string &source, const Translate &translate)
{
    if (!IsValidSource(source))
        return {Status::InvalidInput, {}};
    if (!translate)
        return {Status::ProviderUnavailable, {}};
    try
    {
        auto results = translate({source}, "en", "zh");
        if (results.size() != 1 || results.front().size() > kMaxResultBytes ||
            results.front().find('\0') != std::string::npos || !HasNonWhitespace(results.front()) ||
            !utf8::is_valid(results.front().begin(), results.front().end()))
            return {Status::TranslationFailed, {}};
        return {Status::Success, std::move(results.front())};
    }
    catch (...)
    {
        // Provider exceptions can contain the sentence or credentials. Never
        // forward or log their contents; the UI offers retry or original text.
        return {Status::TranslationFailed, {}};
    }
}
} // namespace SentenceTranslation::detail
