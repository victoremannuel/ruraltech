#line 1 "/Users/victor/Downloads/code/ruraltech/coleira/StateMachine.cpp"
/**
 * @file StateMachine.cpp
 * @brief Seleção de duty cycle por modo.
 */
#include "StateMachine.h"
#include "config.h"

void StateMachine::setMode(CollarMode mode) { mode_ = mode; }

uint32_t StateMachine::intervalMs() const {
  switch (mode_) {
    case CollarMode::ALERTA: return cfg::ALERT_INTERVAL_MS;
    case CollarMode::CONDUCAO: return cfg::HERDING_INTERVAL_MS;
    default: return cfg::NORMAL_INTERVAL_MS;
  }
}
