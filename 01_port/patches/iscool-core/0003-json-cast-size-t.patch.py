#!/usr/bin/env python3
"""Teach iscool::json to cast std::size_t on Darwin.

iscool-core implements its JSON casts one typedef at a time
(`IMPLEMENT_JSON_CAST(unsigned int)`, `IMPLEMENT_JSON_CAST(std::uint64_t)`, ...),
and callers get the right one through the matching `iscool/json/cast_*` header.

Upstream builds on Linux, where `std::uint64_t` *is* `unsigned long`, so
`iscool::json::cast<std::size_t>(value)` resolves to the `uint64_t` cast and
links. On Darwin `uint64_t` is `unsigned long long` while `size_t` is
`unsigned long`, so the same call resolves to nothing and the link fails with
"unsigned long iscool::json::cast<unsigned long>(Json::Value const&)".

This patch adds the missing cast, following the module's own layout:

* `detail/cast_size_t.hpp`  - the `detail::cast<std::size_t>` declaration
* `cast_size_t.hpp`         - `DECLARE_JSON_CAST(std::size_t)`
* `detail/cast_size_t.cpp`  - the definition
* `cast.hpp`                - includes the new header at the end, so every caller
                              of `iscool::json::cast<T>` sees it

Everything is guarded by `__APPLE__`, so a Linux build is unaffected.
Idempotent: running it twice is a no-op.
"""

import pathlib
import sys

root = pathlib.Path(sys.argv[1])

json_module = root / "modules/core/json/module"
include = json_module / "include/iscool/json"
source_dir = json_module / "src/iscool/json/detail"
cmake = root / "build-scripts/cmake/modules/json/CMakeLists.txt"
cast_hpp = include / "cast.hpp"

(include / "detail").mkdir(parents=True, exist_ok=True)
source_dir.mkdir(parents=True, exist_ok=True)

LICENCE = """// SPDX-License-Identifier: Apache-2.0
//
// Port addition, see the comment at the end of iscool/json/cast.hpp.
"""

(include / "detail/cast_size_t.hpp").write_text(
    LICENCE
    + """#pragma once

#if defined(__APPLE__)

  #include <cstddef>

  #include <iscool/json/detail/cast_fwd.hpp>

namespace Json
{
  class Value;
}

namespace iscool
{
  namespace json
  {
    namespace detail
    {
      template <>
      struct cast<std::size_t>
      {
        static bool is_valid(const Json::Value& value);
        static std::size_t value(const Json::Value& value);
      };
    }
  }
}

#endif
"""
)

(include / "cast_size_t.hpp").write_text(
    LICENCE
    + """#pragma once

#if defined(__APPLE__)

  #include <cstddef>

  #include <iscool/json/cast.hpp>
  #include <iscool/json/declare_cast.hpp>
  #include <iscool/json/detail/cast_size_t.hpp>

DECLARE_JSON_CAST(std::size_t);

#endif
"""
)

(source_dir / "cast_size_t.cpp").write_text(
    LICENCE
    + """#include <iscool/json/detail/cast_size_t.hpp>

#if defined(__APPLE__)

  #include <iscool/json/bad_cast.hpp>
  #include <iscool/json/cast.impl.tpp>
  #include <iscool/json/implement_cast.hpp>
  #include <iscool/json/implement_is_of_type.hpp>
  #include <iscool/json/is_of_type.hpp>
  #include <iscool/json/is_of_type.impl.tpp>

  #include <json/value.h>

IMPLEMENT_JSON_CAST(std::size_t)
IMPLEMENT_JSON_IS_OF_TYPE(std::size_t)

bool iscool::json::detail::cast<std::size_t>::is_valid(
    const Json::Value& value)
{
  return value.isUInt64() || (value.isInt64() && (value.asInt64() >= 0));
}

std::size_t
iscool::json::detail::cast<std::size_t>::value(const Json::Value& value)
{
  if (!is_valid(value))
    throw bad_cast(value, "std::size_t");

  return static_cast<std::size_t>(value.asUInt64());
}

#endif
"""
)

text = cmake.read_text()
needle = '  "detail/cast_uint.cpp"'
if needle not in text:
    raise SystemExit(f"patch point not found in {cmake}: detail/cast_uint.cpp")
if '"detail/cast_size_t.cpp"' not in text:
    cmake.write_text(text.replace(needle, needle + '\n  "detail/cast_size_t.cpp"', 1))

text = cast_hpp.read_text()
marker = "// Port addition: std::size_t casts on Darwin."
if marker not in text:
    cast_hpp.write_text(
        text
        + """
// Port addition: std::size_t casts on Darwin. There `size_t` is `unsigned long`, which is
// neither of the integer types this module instantiates its casts for, so the missing cast
// is added and declared here, where every caller of iscool::json::cast<T> picks it up.
#if defined(__APPLE__)
  #include <iscool/json/cast_size_t.hpp>
#endif
"""
    )

print("   patched iscool::json for std::size_t on Darwin")
