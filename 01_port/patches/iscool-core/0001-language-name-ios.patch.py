"""iscool-core 1.25.1: the iOS get_language_name() is stale.

It returns std::string while the header (and the Linux/Android implementations) return
iscool::language_name, so the translation unit does not compile at all. Rewritten to the
current API, keeping the Foundation lookup unchanged.
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
path = root / "modules/core/system/module/src/iscool/system/ios/language_name.mm"
text = path.read_text()
if "iscool::language_name iscool::system::get_language_name()" in text:
    print("   already patched")
    raise SystemExit(0)

path.write_text(
    """// SPDX-License-Identifier: Apache-2.0
#include <iscool/system/language_name.hpp>

#include <iscool/language_name.hpp>

#import <Foundation/Foundation.h>

iscool::language_name iscool::system::get_language_name()
{
    NSString* const language
        ( [ [ NSLocale preferredLanguages ] objectAtIndex: 0 ] );

    NSDictionary* const components
        ( [ NSLocale componentsFromLocaleIdentifier: language ] );

    NSString* const language_name
      ( [ components objectForKey: NSLocaleLanguageCode ] );

    return iscool::from_string_with_fallback([ language_name UTF8String ]);
}
"""
)
print("   patched language_name.mm")
