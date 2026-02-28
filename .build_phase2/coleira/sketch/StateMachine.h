#line 1 "/Users/victor/Downloads/code/ruraltech/coleira/StateMachine.h"
/**
 * @file StateMachine.h
 * @brief Máquina de estado de energia/operação da coleira.
 */
#pragma once
#include "Types.h"

class StateMachine {
 public:
  void setMode(CollarMode mode);
  CollarMode mode() const { return mode_; }
  uint32_t intervalMs() const;

 private:
  CollarMode mode_ = CollarMode::NORMAL;
};
