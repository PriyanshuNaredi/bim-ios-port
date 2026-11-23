// SPDX-License-Identifier: AGPL-3.0-only
//
// iOS entry point for the Bim! port.
//
// The Android app enters through a native activity and the Linux app through main() with
// a command line; on iOS the same `bim::axmol::app::application` is created *before*
// UIApplicationMain because axmol's `AxmolAppController` later calls
// `Application::getInstance()`, and the game itself must be that instance (it derives
// privately from ax::Application). No command line exists on iOS, so the asset directory
// comes from the bundle.

#import <UIKit/UIKit.h>

#include <bim/axmol/app/application.hpp>
#include <bim/axmol/app/bridge.hpp>

#include <axmol/platform/Application.h>

#include <iscool/log/enable_console_log.hpp>

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

namespace
{
  bim::axmol::app::application*
  create_application(bim::axmol::app::bridge*& out_bridge)
  {
    // The assets live in Bim.app/assets, so that is the directory the game scans for
    // animations.json, the sprite sheets and the style files.
    NSString* const resource_path =
        [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"assets"];
    std::vector<std::string> asset_directories{
      resource_path.fileSystemRepresentation ? std::string(resource_path.fileSystemRepresentation)
                                             : std::string()
    };

    CGRect const bounds = [[UIScreen mainScreen] bounds];
    CGFloat const scale = [[UIScreen mainScreen] scale];


    // The bridge is what gives iscool::files, iscool::http and iscool::schedule their
    // platform backends; on desktop it is created in main() before the application, and
    // without it the game dereferences a null file system while loading colors.json.
    out_bridge = new bim::axmol::app::bridge();

    return new bim::axmol::app::application(
        std::move(asset_directories),
        ax::Size(bounds.size.width * scale, bounds.size.height * scale),
        static_cast<float>(scale),
        /* enable_debug */ false, /* script */ nullptr);
  }
}

int main(int argc, char* argv[])
{
  @autoreleasepool
  {
    // Leaked on purpose: the process ends with them, and destroying them after
    // UIApplicationMain returns would touch axmol's globals after the engine has gone.
    // Diagnostics: without this the game fails silently when an asset or a style node is
    // missing. Cheap enough to keep on for now.
    iscool::log::enable_console_log();

    // Debug aid: the simulator console drops buffered diagnostics when the process
    // crashes, and a crash is exactly when they matter.
    {
      NSString* const log_path =
          [NSTemporaryDirectory() stringByAppendingPathComponent:@"diag.log"];
      std::fprintf(stderr, "diag log: %s\n", log_path.fileSystemRepresentation);
      std::freopen(log_path.fileSystemRepresentation, "w", stderr);
      std::setvbuf(stderr, nullptr, _IONBF, 0);
    }

    bim::axmol::app::bridge* bridge = nullptr;
    create_application(bridge);

    return UIApplicationMain(argc, argv, nil, @"GameAppController");
  }
}
