#include "Key/SentenceTranslationPolicy.h"

#include <iostream>
#include <string>
#include <string_view>

namespace
{
int failures = 0;
void Check(bool condition, const char *name)
{
    if (!condition)
    {
        std::cerr << "FAIL: " << name << '\n';
        ++failures;
    }
}
} // namespace

int main()
{
    using namespace SentenceTranslationPolicy;
    const auto sentence = TrailingSource<char16_t>(u"中文 Hello, world!  ", false);
    Check(sentence && sentence->start == 3 && sentence->length == 13, "English suffix after Chinese");
    const auto line = TrailingSource<char16_t>(u"previous\nI like apples.", false);
    Check(line && line->start == 9 && line->length == 14, "line boundary");
    Check(!TrailingSource<char16_t>(u"a truncated English sentence", false), "refuse truncated prefix");
    Check(TrailingSource<char16_t>(u"Hello world.", true).has_value(), "complete document");
    Check(!TrailingSource<char16_t>(u"caf\u00e9 latte", true), "do not silently split accented words");
    Check(!TrailingSource<char16_t>(u"name@example.com", true), "do not translate part of an email");
    Check(!ValidSelectedSource<char16_t>(u"中文 English"), "do not partially translate a selection");
    Check(!ValidSelectedSource<char16_t>(std::u16string(121, u'a')), "bounded request");
    const TargetSnapshot saved{7, 9, 11};
    Check(CanApply(saved, saved, true, true, true), "same target and source");
    Check(!CanApply(saved, {8, 9, 11}, true, true, true), "focus changed");
    Check(!CanApply(saved, {7, 10, 11}, true, true, true), "request changed");
    Check(!CanApply(saved, {7, 9, 12}, true, true, true), "context changed");
    Check(!CanApply(saved, saved, false, true, true), "selection changed");
    Check(!CanApply(saved, saved, true, false, true), "source edited");
    Check(!CanApply(saved, saved, true, true, false), "translation failed");
    return failures ? 1 : 0;
}
