#pragma once

#if __has_include("generated_build_info.h")
#include "generated_build_info.h"
#endif

#ifndef RT_BUILD_GIT_SHA
#define RT_BUILD_GIT_SHA "unknown"
#endif

#ifndef RT_BUILD_GIT_SHORT_SHA
#define RT_BUILD_GIT_SHORT_SHA "unknown"
#endif

#ifndef RT_BUILD_UTC
#define RT_BUILD_UTC __DATE__ " " __TIME__
#endif

#ifndef RT_BUILD_DIRTY
#define RT_BUILD_DIRTY 0
#endif

#ifndef RT_BUILD_SOURCE
#define RT_BUILD_SOURCE "fallback"
#endif

namespace buildinfo {

struct BuildInfo {
  const char* gitSha;
  const char* gitShortSha;
  const char* buildUtc;
  bool dirty;
  const char* buildSource;
};

static inline BuildInfo current() {
  BuildInfo info{};
  info.gitSha = RT_BUILD_GIT_SHA;
  info.gitShortSha = RT_BUILD_GIT_SHORT_SHA;
  info.buildUtc = RT_BUILD_UTC;
  info.dirty = RT_BUILD_DIRTY != 0;
  info.buildSource = RT_BUILD_SOURCE;
  return info;
}

static inline const char* dirtyString(bool dirty) {
  return dirty ? "1" : "0";
}

}  // namespace buildinfo
