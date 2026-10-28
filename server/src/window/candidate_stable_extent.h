#pragma once

#include <algorithm>

// Keep the largest measured extent while respecting the current monitor limit.
// Both values are in DIPs, so a DPI or monitor change can lower the limit.
inline float CandidateStableExtent(float previous, float natural, float limit)
{
    return (std::min)((std::max)(previous, natural), limit);
}
