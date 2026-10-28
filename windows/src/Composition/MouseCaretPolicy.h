#pragma once

#include <algorithm>
#include <cstddef>
#include <limits>
#include <optional>
#include <string>
#include <vector>

namespace FanyImeMouseCaret
{
// The legacy display differs from raw input only by apostrophe separators and
// an already-committed prefix. Refuse to infer a map for other transformations
// such as Japanese or expanded shuangpin; those need the server's explicit map.
inline std::optional<std::vector<std::size_t>> BuildLiteralMap(const std::wstring &raw, const std::wstring &display,
                                                               std::size_t prefixLength)
{
    if (prefixLength > display.size())
        return std::nullopt;
    auto normalize = [](wchar_t ch) { return ch >= L'A' && ch <= L'Z' ? ch + (L'a' - L'A') : ch; };
    std::size_t displayIndex = prefixLength;
    for (const wchar_t rawChar : raw)
    {
        if (rawChar == L'\'')
            continue;
        while (displayIndex < display.size() && display[displayIndex] == L'\'')
            ++displayIndex;
        if (displayIndex == display.size() || normalize(rawChar) != normalize(display[displayIndex]))
            return std::nullopt;
        ++displayIndex;
    }
    while (displayIndex < display.size() && display[displayIndex] == L'\'')
        ++displayIndex;
    if (displayIndex != display.size())
        return std::nullopt;

    std::vector<std::size_t> positions;
    positions.reserve(raw.size() + 1);
    positions.push_back(prefixLength);
    displayIndex = prefixLength;
    for (const wchar_t rawChar : raw)
    {
        if (rawChar == L'\'')
        {
            while (displayIndex < display.size() && display[displayIndex] == L'\'')
                ++displayIndex;
        }
        else
        {
            while (displayIndex < display.size() && display[displayIndex] == L'\'')
                ++displayIndex;
            if (displayIndex < display.size())
                ++displayIndex;
        }
        positions.push_back(displayIndex);
    }
    return positions;
}

// Map an edge in the displayed UTF-16 preedit to a valid raw-key edge. A
// shuangpin expansion can map several displayed positions to one key or vice
// versa. In a tie, keep the raw position nearest the current caret so repeated
// clicks on the same visible edge do not unexpectedly jump across separators.
inline std::optional<std::size_t> NearestRawCaret(const std::vector<std::size_t> &rawToDisplay, std::size_t rawLength,
                                                  std::size_t displayLength, std::size_t currentRawCaret,
                                                  std::size_t displayEdge)
{
    if (rawToDisplay.empty() || rawToDisplay.size() - 1 != rawLength || currentRawCaret > rawLength)
        return std::nullopt;
    for (std::size_t i = 0; i < rawToDisplay.size(); ++i)
        if (rawToDisplay[i] > displayLength || (i > 0 && rawToDisplay[i] < rawToDisplay[i - 1]))
            return std::nullopt;

    displayEdge = (std::min)(displayEdge, displayLength);
    auto distance = [](std::size_t a, std::size_t b) { return a >= b ? a - b : b - a; };
    std::size_t best = 0;
    std::size_t bestDisplayDistance = (std::numeric_limits<std::size_t>::max)();
    std::size_t bestCurrentDistance = (std::numeric_limits<std::size_t>::max)();
    for (std::size_t i = 0; i < rawToDisplay.size(); ++i)
    {
        const std::size_t displayDistance = distance(rawToDisplay[i], displayEdge);
        const std::size_t currentDistance = distance(i, currentRawCaret);
        if (displayDistance < bestDisplayDistance ||
            (displayDistance == bestDisplayDistance && currentDistance < bestCurrentDistance))
        {
            best = i;
            bestDisplayDistance = displayDistance;
            bestCurrentDistance = currentDistance;
        }
    }
    return best;
}
} // namespace FanyImeMouseCaret
