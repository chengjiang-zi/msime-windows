#include "Composition/MouseCaretPolicy.h"

#include <vector>

int main()
{
    using FanyImeMouseCaret::BuildLiteralMap;
    using FanyImeMouseCaret::NearestRawCaret;
    const std::vector<std::size_t> raw{0, 1, 2, 3, 4, 5};
    if (NearestRawCaret(raw, 5, 5, 5, 1) != 1 || NearestRawCaret(raw, 5, 5, 1, 9) != 5)
        return 1;
    // hc expands to hao: the gap has two equally near legal raw positions.
    const std::vector<std::size_t> expanded{0, 1, 2, 4, 6};
    if (NearestRawCaret(expanded, 4, 6, 0, 3) != 2 || NearestRawCaret(expanded, 4, 6, 4, 3) != 3)
        return 2;
    // A committed prefix is not part of the editable raw input.
    if (NearestRawCaret({2, 3, 4}, 2, 4, 2, 0) || NearestRawCaret({2, 3, 4}, 2, 4, 2, 2) != 0)
        return 3;
    // A hidden separator gives two raw edges at the same displayed position.
    if (NearestRawCaret({0, 1, 1, 2}, 3, 2, 2, 1) != 2 || NearestRawCaret({0, 1, 1, 2}, 3, 2, 0, 1) != 1)
        return 4;
    if (NearestRawCaret({}, 0, 0, 0, 0) || NearestRawCaret({0, 2}, 2, 2, 0, 1) ||
        NearestRawCaret({0, 2, 1}, 2, 2, 0, 1) || NearestRawCaret({0, 3}, 1, 2, 0, 1) ||
        NearestRawCaret({0, 1}, 1, 1, 2, 0))
        return 5;
    if (BuildLiteralMap(L"nihao", L"ni'hao", 0) != std::vector<std::size_t>({0, 1, 2, 4, 5, 6}) ||
        BuildLiteralMap(L"ni'hao", L"nihao", 0) != std::vector<std::size_t>({0, 1, 2, 2, 3, 4, 5}) ||
        BuildLiteralMap(L"Ni", L"你好ni", 2) != std::vector<std::size_t>({2, 3, 4}))
        return 6;
    if (BuildLiteralMap(L"hc", L"hao", 0) || BuildLiteralMap(L"abc", L"abcd", 0) || BuildLiteralMap(L"a", L"a", 2))
        return 7;
    return 0;
}
