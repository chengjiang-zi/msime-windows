#pragma once

// The host HWND includes transparent shadow and decoration padding around the
// actual candidate card. Those pixels should not take clicks away from an
// application underneath. Keep the whole host interactive while a popup is
// open, and fail closed if the card has not been laid out yet.
inline bool CandidateReceivesPointer(float x, float y, float left, float top, float width, float height, bool popupOpen)
{
    if (popupOpen || width <= 0.0f || height <= 0.0f)
        return true;
    return x >= left && x < left + width && y >= top && y < top + height;
}
