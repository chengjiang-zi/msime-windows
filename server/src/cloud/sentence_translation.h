#pragma once

#include <functional>
#include <string>
#include <vector>

namespace SentenceTranslation
{
enum class Status
{
    Success,
    InvalidInput,
    ProviderUnavailable,
    TranslationFailed,
};

struct Result
{
    Status status = Status::TranslationFailed;
    std::string text;
};

// The caller invokes this only after an explicit user trigger, off the input
// thread. Neither source nor translated sentence is logged or persisted.
Result TranslateEnglishToChinese(const std::string &source);

namespace detail
{
using Translate =
    std::function<std::vector<std::string>(const std::vector<std::string> &, const std::string &, const std::string &)>;
bool IsValidSource(const std::string &source);
Result TranslateWith(const std::string &source, const Translate &translate);
} // namespace detail
} // namespace SentenceTranslation
