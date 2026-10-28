//
//  LocalizationFormatting.swift
//  Spotifly
//
//  Lightweight helpers for replacing legacy printf-style localization usage.
//

import Foundation

// The key is a `LocalizedStringResource`, not a `String`, so the compiler extracts the literal
// at each call site (`SWIFT_EMIT_LOC_STRINGS`), and `LocalizationTests` sees it as named.
// Interpolating the value into a `Text` key instead, as other strings do, groups its digits:
// "1.007 Tracks" in German, where these say "1007 Tracks" (measured 2026-10-02).

/// - Parameter pluralLocale: whose plural rules pick the form. Without one, the app's own
///   language's, which is also the language the string comes in. A caller that asks for another
///   language's string through the key's locale, as the tests do, passes that locale too: the
///   rules would otherwise follow the app's language, Chinese on a Chinese Mac, which has no
///   singular, and English would read "1 tracks".
func localizedNumberString(_ key: LocalizedStringResource, _ value: Int, pluralLocale: Locale? = nil) -> String {
    // String(format:) is intentional: it handles all printf specifiers (%d, %1$d,
    // multiple occurrences) correctly and produces locale-neutral ASCII digits.
    // .formatted() would insert locale-specific thousands separators and numerals.
    String(format: String(localized: key), locale: pluralLocale, value)
}

/// A page's metadata line, "a · b · c", leaving out the parts it has not got.
func metadataLine(_ parts: String?...) -> String {
    parts.compactMap(\.self).joined(separator: " \(String(localized: "metadata.separator")) ")
}

func localizedTextString(_ key: LocalizedStringResource, _ value: String) -> String {
    // String(format:) is intentional: same reasons as localizedNumberString,
    // plus it correctly handles positional specifiers (%1$@) if ever added.
    String(format: String(localized: key), value)
}
