"""iscool-core 1.25.1: the iOS branch has no open_url().

The generic open_url.cpp only writes a log line, and the iOS file list does not include it,
so every link of an app that opens a URL fails. This adds the real implementation
(UIApplication) and registers it for iOS.
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
implementation = root / "modules/core/system/module/src/iscool/system/ios/open_url.mm"
cmake = root / "build-scripts/cmake/modules/system/CMakeLists.txt"

# 1. the implementation
implementation.write_text(
    """// SPDX-License-Identifier: Apache-2.0
#include <iscool/system/open_url.hpp>

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

void iscool::system::open_url(const std::string& url)
{
  NSString* const text = [NSString stringWithUTF8String:url.c_str()];

  if (text == nil)
    return;

  NSURL* const target = [NSURL URLWithString:text];

  if (target == nil)
    return;

  [[UIApplication sharedApplication] openURL:target
                                     options:@{}
                           completionHandler:nil];
}
"""
)

# 2. its place in the iOS file list
text = cmake.read_text()
if '"ios/open_url.mm"' in text:
    print("   already patched")
    raise SystemExit(0)

needle = '    "ios/language_name.mm"'
if needle not in text:
    raise SystemExit("system/CMakeLists.txt: iOS file list changed upstream")

cmake.write_text(text.replace(needle, needle + '\n    "ios/open_url.mm"', 1))
print("   patched system/CMakeLists.txt + ios/open_url.mm")
