#ifndef RUNNER_HOST_SESSION_OVERLAY_H_
#define RUNNER_HOST_SESSION_OVERLAY_H_

#include <string>

namespace flutter {
class BinaryMessenger;
}

namespace host_session_overlay {

void Initialize(flutter::BinaryMessenger* messenger);
bool Start(const std::wstring& label);
bool Stop();
void Shutdown();

}  // namespace host_session_overlay

#endif  // RUNNER_HOST_SESSION_OVERLAY_H_