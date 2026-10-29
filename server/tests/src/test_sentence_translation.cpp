#include "cloud/sentence_translation.h"
#include "tests/includes/test_framework.h"

#include <stdexcept>
#include <string>

using SentenceTranslation::Status;
using SentenceTranslation::detail::TranslateWith;

TEST_CASE(sentence_translation_sends_one_complete_sentence_in_the_correct_direction)
{
    int calls = 0;
    const auto result =
        TranslateWith("Hello, how are you?", [&](const auto &texts, const auto &source, const auto &target) {
            ++calls;
            REQUIRE_EQ(texts.size(), size_t{1});
            REQUIRE_EQ(texts[0], std::string("Hello, how are you?"));
            REQUIRE_EQ(source, std::string("en"));
            REQUIRE_EQ(target, std::string("zh"));
            return std::vector<std::string>{"你好，你怎么样？"};
        });
    REQUIRE_EQ(calls, 1);
    REQUIRE(result.status == Status::Success);
    REQUIRE_EQ(result.text, std::string("你好，你怎么样？"));
}

TEST_CASE(sentence_translation_rejects_invalid_input_without_sending_it)
{
    int calls = 0;
    auto provider = [&](const auto &, const auto &, const auto &) {
        ++calls;
        return std::vector<std::string>{"unused"};
    };
    REQUIRE(TranslateWith("   \n", provider).status == Status::InvalidInput);
    REQUIRE(TranslateWith(std::string("a\0b", 3), provider).status == Status::InvalidInput);
    REQUIRE(TranslateWith(std::string(1001, 'a'), provider).status == Status::InvalidInput);
    REQUIRE(TranslateWith(std::string("\xff", 1), provider).status == Status::InvalidInput);
    REQUIRE_EQ(calls, 0);
}

TEST_CASE(sentence_translation_returns_failure_without_guessing_or_exposing_errors)
{
    REQUIRE(TranslateWith("Hello", {}).status == Status::ProviderUnavailable);
    const auto empty =
        TranslateWith("Hello", [](const auto &, const auto &, const auto &) { return std::vector<std::string>{"  "}; });
    REQUIRE(empty.status == Status::TranslationFailed);
    REQUIRE(empty.text.empty());
    const auto exception =
        TranslateWith("Hello", [](const auto &, const auto &, const auto &) -> std::vector<std::string> {
            throw std::runtime_error("sensitive provider details");
        });
    REQUIRE(exception.status == Status::TranslationFailed);
    REQUIRE(exception.text.empty());
    const auto multiple = TranslateWith(
        "Hello", [](const auto &, const auto &, const auto &) { return std::vector<std::string>{"one", "two"}; });
    REQUIRE(multiple.status == Status::TranslationFailed);
}
