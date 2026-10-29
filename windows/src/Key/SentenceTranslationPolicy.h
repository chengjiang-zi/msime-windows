#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>

namespace SentenceTranslationPolicy
{
// Initial transport must fit the existing UTF-16 request frame, including its
// terminator. Never translate a silently truncated sentence.
inline constexpr std::size_t kMaxSourceCodeUnits = 120;

struct Span
{
    std::size_t start;
    std::size_t length;
};

template <class Char> bool IsEnglishCharacter(Char ch)
{
    return (ch >= Char('a') && ch <= Char('z')) || (ch >= Char('A') && ch <= Char('Z')) ||
           (ch >= Char('0') && ch <= Char('9')) || ch == Char(' ') || ch == Char('\t') || ch == Char(',') ||
           ch == Char('.') || ch == Char('!') || ch == Char('?') || ch == Char('\'') || ch == Char('"') ||
           ch == Char('-') || ch == Char(':') || ch == Char(';') || ch == Char('(') || ch == Char(')');
}

template <class Char> bool IsEnglishLetter(Char ch)
{
    return (ch >= Char('a') && ch <= Char('z')) || (ch >= Char('A') && ch <= Char('Z'));
}

// A selected span must be wholly supported. Do not send a partial selection.
template <class Char> bool ValidSelectedSource(std::basic_string_view<Char> text)
{
    if (text.empty() || text.size() > kMaxSourceCodeUnits)
        return false;
    bool hasLetter = false;
    for (Char ch : text)
    {
        if (!IsEnglishCharacter(ch))
            return false;
        hasLetter = hasLetter || IsEnglishLetter(ch);
    }
    return hasLetter;
}

// Pick the trailing English block from the same line. `reachedStart` says the
// host really exposed the beginning; if our bounded read stopped amid an
// English block, decline rather than sending only its final characters.
template <class Char> std::optional<Span> TrailingSource(std::basic_string_view<Char> beforeCaret, bool reachedStart)
{
    if (beforeCaret.empty())
        return std::nullopt;
    std::size_t end = beforeCaret.size();
    while (end > 0 && (beforeCaret[end - 1] == Char(' ') || beforeCaret[end - 1] == Char('\t')))
        --end;
    std::size_t begin = end;
    while (begin > 0 && IsEnglishCharacter(beforeCaret[begin - 1]))
        --begin;
    const std::size_t rawBegin = begin;
    if (rawBegin == 0 && !reachedStart)
        return std::nullopt;
    if (rawBegin > 0)
    {
        const auto boundary = static_cast<std::uint32_t>(beforeCaret[rawBegin - 1]);
        const bool supportedBoundary =
            boundary == '\n' || boundary == '\r' || (boundary >= 0x3400 && boundary <= 0x9fff) ||
            (boundary >= 0x3000 && boundary <= 0x303f) || (boundary >= 0xff00 && boundary <= 0xffef);
        if (!supportedBoundary)
            return std::nullopt;
    }
    while (begin < end && (beforeCaret[begin] == Char(' ') || beforeCaret[begin] == Char('\t')))
        ++begin;
    const auto text = beforeCaret.substr(begin, end - begin);
    if (!ValidSelectedSource(text))
        return std::nullopt;
    return Span{begin, end - begin};
}

struct TargetSnapshot
{
    std::uint64_t focusToken = 0;
    std::uint64_t requestId = 0;
    std::uint64_t contextEpoch = 0;
};

inline bool CanApply(const TargetSnapshot &original, const TargetSnapshot &current, bool sameRange, bool sameSource,
                     bool resultValid)
{
    return original.focusToken != 0 && original.requestId != 0 && original.contextEpoch != 0 &&
           original.focusToken == current.focusToken && original.requestId == current.requestId &&
           original.contextEpoch == current.contextEpoch && sameRange && sameSource && resultValid;
}
} // namespace SentenceTranslationPolicy
