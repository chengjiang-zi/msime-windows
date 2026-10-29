#pragma once

#include <algorithm>
#include <charconv>
#include <cstdint>
#include <string_view>
#include <system_error>

// Physical screen coordinates. Keep at least the card's top-left visible when
// the monitor is too small for it; callers choose the nearest live work area.
struct CandidateFixedRect
{
    int left;
    int top;
    int right;
    int bottom;
};

struct CandidateFixedPoint
{
    int x;
    int y;
};

inline bool ParseCandidateFixedPoint(std::string_view value, CandidateFixedPoint &point)
{
    const auto comma = value.find(',');
    if (value.empty() || value.size() > 23 || comma == std::string_view::npos || comma == 0 ||
        comma + 1 == value.size() || value.find(',', comma + 1) != std::string_view::npos)
        return false;
    int x = 0;
    int y = 0;
    const auto first = std::from_chars(value.data(), value.data() + comma, x);
    const auto second = std::from_chars(value.data() + comma + 1, value.data() + value.size(), y);
    if (first.ec != std::errc{} || first.ptr != value.data() + comma || second.ec != std::errc{} ||
        second.ptr != value.data() + value.size())
        return false;
    point = {x, y};
    return true;
}

inline CandidateFixedPoint ClampCandidateFixedPoint(CandidateFixedPoint requested, int cardWidth, int cardHeight,
                                                    CandidateFixedRect workArea)
{
    using Wide = std::int64_t;
    const Wide left = workArea.left;
    const Wide top = workArea.top;
    const Wide right = (std::max)(left, static_cast<Wide>(workArea.right));
    const Wide bottom = (std::max)(top, static_cast<Wide>(workArea.bottom));
    const Wide width = (std::max)(Wide{0}, static_cast<Wide>(cardWidth));
    const Wide height = (std::max)(Wide{0}, static_cast<Wide>(cardHeight));
    const Wide maxX = (std::max)(left, right - width);
    const Wide maxY = (std::max)(top, bottom - height);
    return {static_cast<int>((std::clamp)(static_cast<Wide>(requested.x), left, maxX)),
            static_cast<int>((std::clamp)(static_cast<Wide>(requested.y), top, maxY))};
}
