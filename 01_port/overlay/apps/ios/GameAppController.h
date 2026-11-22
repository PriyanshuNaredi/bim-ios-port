// SPDX-License-Identifier: AGPL-3.0-only
#pragma once

#import <axmol/platform/ios/AxmolAppController.h>

/// iOS port addition: axmol's controller already builds the render view, attaches it to
/// the director and runs the application, and the Bim! application is that application
/// (created in main.mm before UIApplicationMain), so nothing has to be overridden yet.
@interface GameAppController : AxmolAppController
@end
