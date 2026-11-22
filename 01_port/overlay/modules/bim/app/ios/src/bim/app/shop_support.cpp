// SPDX-License-Identifier: AGPL-3.0-only
//
// iOS port addition. No StoreKit purchase path is wired, so the shop must not pretend
// to sell anything: the app then shows its existing "the shop is not available on this
// platform" message instead of an offer that cannot complete.
#include <bim/app/shop_support.hpp>

bool bim::app::is_shop_supported()
{
  return false;
}
