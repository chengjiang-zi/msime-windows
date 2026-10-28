#include "Globals.h"
#include "Private.h"
#include "resource.h"
#include "define.h"
#include "MetasequoiaIMEBaseStructure.h"
#include <unordered_set>
#include <windows.h>
#include <fstream>
#include <string>
#include <ctime>
#include "FanyUtils.h"

namespace Global
{
HINSTANCE dllInstanceHandle;

LONG dllRefCount = -1;

CRITICAL_SECTION CS;
HFONT defaultlFontHandle; // Global font object we use everywhere

//---------------------------------------------------------------------
// MetasequoiaIME CLSID
//---------------------------------------------------------------------
// {56A47253-A7C1-53AC-9028-7297207BD972}
extern const CLSID MetasequoiaIMECLSID = {0x56a47253, 0xa7c1, 0x53ac, {0x90, 0x28, 0x72, 0x97, 0x20, 0x7b, 0xd9, 0x72}};

//---------------------------------------------------------------------
// Profile GUID
//---------------------------------------------------------------------
// {1CAC6601-4479-55C1-BCA3-2B46B9AFD375}
extern const GUID MetasequoiaIMEGuidProfile = {
    0x1cac6601, 0x4479, 0x55c1, {0xbc, 0xa3, 0x2b, 0x46, 0xb9, 0xaf, 0xd3, 0x75}};

//---------------------------------------------------------------------
// PreserveKey GUID
//---------------------------------------------------------------------
// {1D1E6D9A-24B3-57FF-8897-A1C5A4418CBE}
extern const GUID MetasequoiaIMEGuidImeModePreserveKey = {
    0x1d1e6d9a, 0x24b3, 0x57ff, {0x88, 0x97, 0xa1, 0xc5, 0xa4, 0x41, 0x8c, 0xbe}};

// {2CF3396F-B029-5361-9621-E9DBBEB2DACD}
extern const GUID MetasequoiaIMEGuidImeModePreserveKey02 = {
    0x2cf3396f, 0xb029, 0x5361, {0x96, 0x21, 0xe9, 0xdb, 0xbe, 0xb2, 0xda, 0xcd}};

// {AA823891-3256-5D71-B883-CC2159860658}
extern const GUID MetasequoiaIMEGuidImeModePreserveKey03 = {
    0xaa823891, 0x3256, 0x5d71, {0xb8, 0x83, 0xcc, 0x21, 0x59, 0x86, 0x06, 0x58}};

// {1611880D-CD6F-5519-903B-0E13F1ED499D}
extern const GUID MetasequoiaIMEGuidEnglishInputModePreserveKey = {
    0x1611880d, 0xcd6f, 0x5519, {0x90, 0x3b, 0x0e, 0x13, 0xf1, 0xed, 0x49, 0x9d}};

// {150A6C1C-4195-51C6-BC91-AE07FDEC04DA}
extern const GUID MetasequoiaIMEGuidDoubleSingleBytePreserveKey = {
    0x150a6c1c, 0x4195, 0x51c6, {0xbc, 0x91, 0xae, 0x07, 0xfd, 0xec, 0x04, 0xda}};

// {9EA0ACB6-B1B1-58FC-A43D-EC8FBE06F1BE}
extern const GUID MetasequoiaIMEGuidPunctuationPreserveKey = {
    0x9ea0acb6, 0xb1b1, 0x58fc, {0xa4, 0x3d, 0xec, 0x8f, 0xbe, 0x06, 0xf1, 0xbe}};

//---------------------------------------------------------------------
// Compartments
//---------------------------------------------------------------------
// {7C1ED6A1-4953-5600-A027-DB9AB5413CE5}
extern const GUID MetasequoiaIMEGuidCompartmentDoubleSingleByte = {
    0x7c1ed6a1, 0x4953, 0x5600, {0xa0, 0x27, 0xdb, 0x9a, 0xb5, 0x41, 0x3c, 0xe5}};

// {C91CEB87-B0C0-5005-B5D2-5E92F06F8582}
extern const GUID MetasequoiaIMEGuidCompartmentPunctuation = {
    0xc91ceb87, 0xb0c0, 0x5005, {0xb5, 0xd2, 0x5e, 0x92, 0xf0, 0x6f, 0x85, 0x82}};

//---------------------------------------------------------------------
// LanguageBars
//---------------------------------------------------------------------

// {77D726AB-282E-582D-9281-41A49CF95C86}
extern const GUID MetasequoiaIMEGuidLangBarIMEMode = {
    0x77d726ab, 0x282e, 0x582d, {0x92, 0x81, 0x41, 0xa4, 0x9c, 0xf9, 0x5c, 0x86}};

// {5564CBBF-3F95-5973-985E-B6665C3066DF}
extern const GUID MetasequoiaIMEGuidLangBarDoubleSingleByte = {
    0x5564cbbf, 0x3f95, 0x5973, {0x98, 0x5e, 0xb6, 0x66, 0x5c, 0x30, 0x66, 0xdf}};

// {59E30294-935C-5AA3-B275-B8523356B83F}
extern const GUID MetasequoiaIMEGuidLangBarPunctuation = {
    0x59e30294, 0x935c, 0x5aa3, {0xb2, 0x75, 0xb8, 0x52, 0x33, 0x56, 0xb8, 0x3f}};

// {DCB22000-4499-546D-B9D3-D17DB6F44556}
extern const GUID MetasequoiaIMEGuidDisplayAttributeInput = {
    0xdcb22000, 0x4499, 0x546d, {0xb9, 0xd3, 0xd1, 0x7d, 0xb6, 0xf4, 0x45, 0x56}};

// {9E697B04-B3D9-5E99-A246-B29EF1624ED2}
extern const GUID MetasequoiaIMEGuidDisplayAttributeConverted = {
    0x9e697b04, 0xb3d9, 0x5e99, {0xa2, 0x46, 0xb2, 0x9e, 0xf1, 0x62, 0x4e, 0xd2}};

//---------------------------------------------------------------------
// UI element
//---------------------------------------------------------------------

// {F39DE421-BBCC-57BB-979A-9860C992AD21}
extern const GUID MetasequoiaIMEGuidCandUIElement = {
    0xf39de421, 0xbbcc, 0x57bb, {0x97, 0x9a, 0x98, 0x60, 0xc9, 0x92, 0xad, 0x21}};

//---------------------------------------------------------------------
// Unicode byte order mark
//---------------------------------------------------------------------
extern const WCHAR UnicodeByteOrderMark = 0xFEFF;

//---------------------------------------------------------------------
// dictionary table delimiter
//---------------------------------------------------------------------
extern const WCHAR KeywordDelimiter = L'=';
extern const WCHAR StringDelimiter = L'\"';

//---------------------------------------------------------------------
// defined item in setting file table [PreservedKey] section
//---------------------------------------------------------------------
extern const WCHAR ImeModeDescription[] = L"Chinese/English input (Shift)";
extern const WCHAR ImeModeDescription02[] = L"Chinese/English input (Ctrl+Alt+Space)";
extern const WCHAR ImeModeDescription03[] = L"Chinese/English input (Ctrl)";
extern const WCHAR EnglishInputModeDescription[] = L"English candidate input";
extern const int ImeModeOnIcoIndex = IME_MODE_ON_ICON_INDEX;
extern const int ImeModeOffIcoIndex = IME_MODE_OFF_ICON_INDEX;

extern const WCHAR DoubleSingleByteDescription[] = L"Double/Single byte";
extern const int DoubleSingleByteOnIcoIndex = IME_DOUBLE_ON_INDEX;
extern const int DoubleSingleByteOffIcoIndex = IME_DOUBLE_OFF_INDEX;

extern const WCHAR PunctuationDescription[] = L"Chinese/English punctuation";
extern const int PunctuationOnIcoIndex = IME_PUNCTUATION_ON_INDEX;
extern const int PunctuationOffIcoIndex = IME_PUNCTUATION_OFF_INDEX;

//---------------------------------------------------------------------
// defined item in setting file table [LanguageBar] section
//---------------------------------------------------------------------
extern const WCHAR LangbarImeModeDescription[] = L"Conversion mode";
extern const WCHAR LangbarDoubleSingleByteDescription[] = L"Character width";
extern const WCHAR LangbarPunctuationDescription[] = L"Punctuation";

//---------------------------------------------------------------------
// defined full width characters for Double/Single byte conversion
//---------------------------------------------------------------------
extern const WCHAR FullWidthCharTable[] = {
    0x3000, // Full width space
    0xFF01, // ！
    0xFF02, // ＂
    0xFF03, // ＃
    0xFF04, // ＄
    0xFF05, // ％
    0xFF06, // ＆
    0xFF07, // ＇
    0xFF08, // （
    0xFF09, // ）
    0xFF0A, // ＊
    0xFF0B, // ＋
    0xFF0C, // ，
    0xFF0D, // －
    0xFF0E, // ．
    0xFF0F, // ／

    0xFF10, // ０
    0xFF11, // １
    0xFF12, // ２
    0xFF13, // ３
    0xFF14, // ４
    0xFF15, // ５
    0xFF16, // ６
    0xFF17, // ７
    0xFF18, // ８
    0xFF19, // ９
    0xFF1A, // ：
    0xFF1B, // ；
    0xFF1C, // ＜
    0xFF1D, // ＝
    0xFF1E, // ＞
    0xFF1F, // ？

    0xFF20, // ＠
    0xFF21, // Ａ
    0xFF22, // Ｂ
    0xFF23, // Ｃ
    0xFF24, // Ｄ
    0xFF25, // Ｅ
    0xFF26, // Ｆ
    0xFF27, // Ｇ
    0xFF28, // Ｈ
    0xFF29, // Ｉ
    0xFF2A, // Ｊ
    0xFF2B, // Ｋ
    0xFF2C, // Ｌ
    0xFF2D, // Ｍ
    0xFF2E, // Ｎ
    0xFF2F, // Ｏ

    0xFF30, // Ｐ
    0xFF31, // Ｑ
    0xFF32, // Ｒ
    0xFF33, // Ｓ
    0xFF34, // Ｔ
    0xFF35, // Ｕ
    0xFF36, // Ｖ
    0xFF37, // Ｗ
    0xFF38, // Ｘ
    0xFF39, // Ｙ
    0xFF3A, // Ｚ
    0xFF3B, // ［
    0xFF3C, // ＼
    0xFF3D, // ］
    0xFF3E, // ＾
    0xFF3F, // ＿

    0xFF40, // ｀
    0xFF41, // ａ
    0xFF42, // ｂ
    0xFF43, // ｃ
    0xFF44, // ｄ
    0xFF45, // ｅ
    0xFF46, // ｆ
    0xFF47, // ｇ
    0xFF48, // ｈ
    0xFF49, // ｉ
    0xFF4A, // ｊ
    0xFF4B, // ｋ
    0xFF4C, // ｌ
    0xFF4D, // ｍ
    0xFF4E, // ｎ
    0xFF4F, // ｏ

    0xFF50, // ｐ
    0xFF51, // ｑ
    0xFF52, // ｒ
    0xFF53, // ｓ
    0xFF54, // ｔ
    0xFF55, // ｕ
    0xFF56, // ｖ
    0xFF57, // ｗ
    0xFF58, // ｘ
    0xFF59, // ｙ
    0xFF5A, // ｚ
    0xFF5B, // ｛
    0xFF5C, // ｜
    0xFF5D, // ｝
    0xFF5E  // ～
};

//---------------------------------------------------------------------
// defined punctuation characters
//---------------------------------------------------------------------
// '<' and '>' are deliberately absent: they belong to the nest pair set up in
// SetupPunctuationPair, and GetPunctuation searches this table first. Listing them here
// would shadow the nest pair, and the nested marks would never be produced.
extern const struct _PUNCTUATION PunctuationTable[23] = {
    {L'`', L"·"},   // ·
    {L'~', L"~"},   // ~
    {L'!', L"！"},  // ！
    {L'@', L"@"},   // @
    {L'#', L"#"},   // #
    {L'$', L"￥"},  // ￥
    {L'%', L"%"},   // %
    {L'^', L"……"},  // ……
    {L'&', L"&"},   // &
    {L'*', L"*"},   // *
    {L'(', L"（"},  // （
    {L')', L"）"},  // ）
    {L'_', L"——"},  // ——
    {L'[', L"【"},  // 【
    {L']', L"】"},  // 】
    {L'{', L"{"},   // {
    {L'}', L"}"},   // }
    {L'\\', L"、"}, // 、
    {L';', L"；"},  // ；
    {L':', L"："},  // ：
    {L',', L"，"},  // ，
    {L'.', L"。"},  // 。
    {L'?', L"？"},  // ？
};

//
// Will commit the highlighted candidate string with a punctuation character.
//
extern const std::unordered_set<WCHAR> CommitWithHighlightedCandPunc = {
    L'`',  //
    L'!',  //
    L'@',  //
    L'#',  //
    L'$',  //
    L'%',  //
    L'^',  //
    L'&',  //
    L'*',  //
    L'(',  //
    L')',  //
    L'-',  //
    L'_',  //
    L'=',  //
    L'+',  //
    L'[',  //
    L']',  //
    L'\\', //
    L'/',  //
    L';',  //
    L':',  //
    L'\'', //
    L'"',  //
    L',',  //
    L'<',  //
    L'.',  //
    L'>',  //
    L'?'   //
};

//+---------------------------------------------------------------------------
//
// CheckModifiers
//
//----------------------------------------------------------------------------

#define TF_MOD_ALLALT (TF_MOD_RALT | TF_MOD_LALT | TF_MOD_ALT)
#define TF_MOD_ALLCONTROL (TF_MOD_RCONTROL | TF_MOD_LCONTROL | TF_MOD_CONTROL)
#define TF_MOD_ALLSHIFT (TF_MOD_RSHIFT | TF_MOD_LSHIFT | TF_MOD_SHIFT)
#define TF_MOD_RLALT (TF_MOD_RALT | TF_MOD_LALT)
#define TF_MOD_RLCONTROL (TF_MOD_RCONTROL | TF_MOD_LCONTROL)
#define TF_MOD_RLSHIFT (TF_MOD_RSHIFT | TF_MOD_LSHIFT)

#define CheckMod(m0, m1, mod)                                                                                          \
    if (m1 & TF_MOD_##mod##)                                                                                           \
    {                                                                                                                  \
        if (!(m0 & TF_MOD_##mod##))                                                                                    \
        {                                                                                                              \
            return FALSE;                                                                                              \
        }                                                                                                              \
    }                                                                                                                  \
    else                                                                                                               \
    {                                                                                                                  \
        if ((m1 ^ m0) & TF_MOD_RL##mod##)                                                                              \
        {                                                                                                              \
            return FALSE;                                                                                              \
        }                                                                                                              \
    }

BOOL CheckModifiers(UINT modCurrent, UINT mod)
{
    mod &= ~TF_MOD_ON_KEYUP;

    if (mod & TF_MOD_IGNORE_ALL_MODIFIER)
    {
        return TRUE;
    }

    if (modCurrent == mod)
    {
        return TRUE;
    }

    if (modCurrent && !mod)
    {
        return FALSE;
    }

    CheckMod(modCurrent, mod, ALT);
    CheckMod(modCurrent, mod, SHIFT);
    CheckMod(modCurrent, mod, CONTROL);

    return TRUE;
}

//+---------------------------------------------------------------------------
//
// UpdateModifiers
//
//    wParam - virtual-key code
//    lParam - [0-15]  Repeat count
//  [16-23] Scan code
//  [24]    Extended key
//  [25-28] Reserved
//  [29]    Context code
//  [30]    Previous key state
//  [31]    Transition state
//----------------------------------------------------------------------------

thread_local USHORT ModifiersValue = 0;
thread_local BOOL IsShiftKeyDownOnly = FALSE;
thread_local BOOL IsControlKeyDownOnly = FALSE;
thread_local BOOL IsAltKeyDownOnly = FALSE;
thread_local BOOL PureShiftKeyDown = FALSE;
thread_local BOOL PureShiftKeyUp = FALSE;

BOOL UpdateModifiers(WPARAM wParam, LPARAM lParam)
{
    // high-order bit : key down
    // low-order bit  : toggled
    SHORT sksMenu = GetKeyState(VK_MENU);
    SHORT sksCtrl = GetKeyState(VK_CONTROL);
    SHORT sksShft = GetKeyState(VK_SHIFT);

    PureShiftKeyUp = FALSE;

    switch (wParam & 0xff)
    {
    case VK_MENU:
        // is VK_MENU down?
        if (sksMenu & 0x8000)
        {
            // is extended key?
            if (lParam & 0x01000000)
            {
                ModifiersValue |= (TF_MOD_RALT | TF_MOD_ALT);
            }
            else
            {
                ModifiersValue |= (TF_MOD_LALT | TF_MOD_ALT);
            }

            // is previous key state up?
            if (!(lParam & 0x40000000))
            {
                // is VK_CONTROL and VK_SHIFT up?
                if (!(sksCtrl & 0x8000) && !(sksShft & 0x8000))
                {
                    IsAltKeyDownOnly = TRUE;
                }
                else
                {
                    IsShiftKeyDownOnly = FALSE;
                    IsControlKeyDownOnly = FALSE;
                    IsAltKeyDownOnly = FALSE;
                }
            }
        }
        break;

    case VK_CONTROL:
        // is VK_CONTROL down?
        if (sksCtrl & 0x8000)
        {
            // is extended key?
            if (lParam & 0x01000000)
            {
                ModifiersValue |= (TF_MOD_RCONTROL | TF_MOD_CONTROL);
            }
            else
            {
                ModifiersValue |= (TF_MOD_LCONTROL | TF_MOD_CONTROL);
            }

            // is previous key state up?
            if (!(lParam & 0x40000000))
            {
                // is VK_SHIFT and VK_MENU up?
                if (!(sksShft & 0x8000) && !(sksMenu & 0x8000))
                {
                    IsControlKeyDownOnly = TRUE;
                }
                else
                {
                    IsShiftKeyDownOnly = FALSE;
                    IsControlKeyDownOnly = FALSE;
                    IsAltKeyDownOnly = FALSE;
                }
            }
        }
        break;

    case VK_SHIFT: {
        // is VK_SHIFT down?
        if (sksShft & 0x8000)
        {
            PureShiftKeyDown = TRUE;
            // is scan code 0x36(right shift)?
            if (((lParam >> 16) & 0x00ff) == 0x36)
            {
                ModifiersValue |= (TF_MOD_RSHIFT | TF_MOD_SHIFT);
            }
            else
            {
                ModifiersValue |= (TF_MOD_LSHIFT | TF_MOD_SHIFT);
            }

            // is previous key state up?
            if (!(lParam & 0x40000000))
            {
                // is VK_MENU and VK_CONTROL up?
                if (!(sksMenu & 0x8000) && !(sksCtrl & 0x8000))
                {
                    IsShiftKeyDownOnly = TRUE;
                }
                else
                {
                    IsShiftKeyDownOnly = FALSE;
                    IsControlKeyDownOnly = FALSE;
                    IsAltKeyDownOnly = FALSE;
                }
            }
        }
        else
        {
            if (PureShiftKeyDown)
                PureShiftKeyUp = TRUE;
        }
        break;
    }

    default:
        IsShiftKeyDownOnly = FALSE;
        IsControlKeyDownOnly = FALSE;
        IsAltKeyDownOnly = FALSE;
        PureShiftKeyDown = FALSE;
        break;
    }

    if (!(sksMenu & 0x8000))
    {
        ModifiersValue &= ~TF_MOD_ALLALT;
    }
    if (!(sksCtrl & 0x8000))
    {
        ModifiersValue &= ~TF_MOD_ALLCONTROL;
    }
    if (!(sksShft & 0x8000))
    {
        ModifiersValue &= ~TF_MOD_ALLSHIFT;
    }

    return TRUE;
}

//---------------------------------------------------------------------
// override CompareElements
//---------------------------------------------------------------------
BOOL CompareElements(LCID locale, const CStringRange *pElement1, const CStringRange *pElement2)
{
    return (CStringRange::Compare(locale, (CStringRange *)pElement1, (CStringRange *)pElement2) == CSTR_EQUAL) ? TRUE
                                                                                                               : FALSE;
}
} // namespace Global
