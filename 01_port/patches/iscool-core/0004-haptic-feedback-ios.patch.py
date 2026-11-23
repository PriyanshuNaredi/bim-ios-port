#!/usr/bin/env python3
"""Give iscool::system::haptic_feedback an iOS implementation.

`iscool/system/haptic_feedback.hpp` picks the Android implementation on Android and the
"mockup" everywhere else, so on iOS the Vibrations setting does nothing and
`haptic_feedback::click()` - called from the game when a bomb goes off - is empty.

This patch adds `ios/haptic_feedback.{hpp,mm}` backed by UIImpactFeedbackGenerator, selects
it on Apple platforms, and registers the source in the system module.

Idempotent: running it twice is a no-op.
"""

import pathlib
import sys

root = pathlib.Path(sys.argv[1])

module = root / "modules/core/system/module"
header_ios = module / "include/iscool/system/ios/haptic_feedback.hpp"
source_ios = module / "src/iscool/system/ios/haptic_feedback.mm"
dispatcher = module / "include/iscool/system/haptic_feedback.hpp"
cmake = root / "build-scripts/cmake/modules/system/CMakeLists.txt"

header_ios.parent.mkdir(parents=True, exist_ok=True)
source_ios.parent.mkdir(parents=True, exist_ok=True)

header_ios.write_text(
    """// SPDX-License-Identifier: Apache-2.0
//
// Port addition: the iOS implementation of iscool::system::haptic_feedback.
#pragma once

namespace iscool::system
{
  class haptic_feedback
  {
  public:
    haptic_feedback();
    ~haptic_feedback();

    haptic_feedback(const haptic_feedback&) = delete;
    haptic_feedback& operator=(const haptic_feedback&) = delete;

    bool is_enabled() const;
    void set_enabled(bool enabled);

    void click();

  private:
    bool m_enabled;
  };
}
"""
)

source_ios.write_text(
    """// SPDX-License-Identifier: Apache-2.0
//
// Port addition: the iOS implementation of iscool::system::haptic_feedback, on top of
// UIImpactFeedbackGenerator. The generator is prepared before each click, which is what
// keeps the latency low enough for a bomb going off.
#include <iscool/system/ios/haptic_feedback.hpp>

#import <UIKit/UIKit.h>

namespace iscool::system::detail
{
  void impact()
  {
    UIImpactFeedbackGenerator* const generator =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];

    [generator prepare];
    [generator impactOccurred];
  }
}

iscool::system::haptic_feedback::haptic_feedback()
  : m_enabled(false)
{}

iscool::system::haptic_feedback::~haptic_feedback() = default;

bool iscool::system::haptic_feedback::is_enabled() const
{
  return m_enabled;
}

void iscool::system::haptic_feedback::set_enabled(bool enabled)
{
  m_enabled = enabled;
}

void iscool::system::haptic_feedback::click()
{
  if (!m_enabled)
    return;

  if (![NSThread isMainThread])
    {
      dispatch_async(dispatch_get_main_queue(), ^{ iscool::system::detail::impact(); });
      return;
    }

  iscool::system::detail::impact();
}
"""
)

text = dispatcher.read_text()
if "iscool/system/ios/haptic_feedback.hpp" not in text:
    text = text.replace(
        """#ifdef __ANDROID__
  #include <iscool/system/android/haptic_feedback.hpp>
#else""",
        """#ifdef __ANDROID__
  #include <iscool/system/android/haptic_feedback.hpp>
#elif defined(__APPLE__)
  #include <iscool/system/ios/haptic_feedback.hpp>
#else""",
        1,
    )
    dispatcher.write_text(text)

text = cmake.read_text()

# The mockup is the fallback for every non-Android, non-Apple platform. Leaving it in the iOS
# list defines the class twice, so remove it from the iOS branch only.
mockup_in_ios = '    "detail/haptic_feedback_mockup.cpp"\n\n    "ios/application_id.mm"'
if mockup_in_ios in text:
    text = text.replace(mockup_in_ios, '    "ios/application_id.mm"', 1)

if '"ios/haptic_feedback.mm"' not in text:
    text = text.replace(
        '    "ios/device_model.mm"',
        '    "ios/device_model.mm"\n    "ios/haptic_feedback.mm"',
        1,
    )

cmake.write_text(text)

print("   patched iscool::system::haptic_feedback for iOS")
