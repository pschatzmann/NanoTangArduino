#pragma once

#include <Arduino.h>

/* On-chip INT8 dot-product accelerator: same compute engine
 * (dot_product_engine.v) and host API shape as the standalone NanoTangAI
 * project's SPI-attached TangNanoAccelerator, but wired directly onto
 * this core's own picorv32 bus (gateware/src/ai_accel_bus.v) instead of
 * going through an external SPI link to a second Tang Nano 20K board -
 * see docs/PERIPHERALS.md "AI accelerator".
 *
 * Differences from NanoTangAI's TangNanoAccelerator, all because there's
 * no separate link to manage:
 *   - begin() takes no SPI object/CS pin/clock speed.
 *   - No ping()/protocolVersion() - there's nothing to probe; if this
 *     bitstream is running, the accelerator is there.
 *   - No computeDelayMicros(): getResults()'s first register read blocks
 *     (via bus backpressure, not a software poll loop or a delay sized
 *     from a cycle-count formula) until the engine's `done` actually
 *     fires. Subsequent reads for the same compute() return immediately.
 *
 * Usage mirrors dspsDotProdS8()'s role in TinyTTS's Ops.h (see NanoTangAI's
 * own docs/architecture.md): load a kWeightTileRows-row weight tile once
 * (loadWeights()), then for each timestep's gathered activation window,
 * compute() followed directly by getResults() (no delay needed) returns
 * the same raw INT8xINT8->INT32 dot products dspsDotProdS8() would have,
 * one per (row, tap) - rescaling (x_scale/w_rowScale/bias) is unchanged,
 * still done by the caller in float, exactly as Ops.h's conv1d() already
 * does.
 */
class AIAcceleratorClass
{
public:
  /// Nothing to initialize - the accelerator is always present in this
  /// core's gateware. Kept for API familiarity with NanoTangAI's begin().
  void begin(void) {}

  /// Must be called once before loadWeights()/compute() - tells the
  /// engine the shape it should expect. `rows` must be <= 8 and
  /// `cinPadded` must be a multiple of 16 (the gateware's fixed
  /// ROWS/LANES parameters - see gateware/src/ai_accel_bus.v).
  void config(uint16_t cinPadded, uint8_t k, uint8_t rows)
  {
    cinPadded_ = cinPadded;
    k_ = k;
    rows_ = rows;
    TANGNANO20K_AI_CFG_REG = ((uint32_t)rows << 24) | ((uint32_t)k << 16) | cinPadded;
  }

  /// `data` is `rows*k*cinPadded` INT8 bytes, row-major: row0's
  /// `k*cinPadded` bytes (tap-major, `[tap][cinPadded]`) then row1's, etc -
  /// exactly the tile layout TinyTTS's Ops.h already builds for INT8
  /// weights. Must be called after config().
  void loadWeights(const int8_t *data, size_t len)
  {
    (void)len;
    size_t rowBytes = (size_t)k_ * cinPadded_;
    const uint8_t *bytes = (const uint8_t *)data;

    for (uint8_t row = 0; row < rows_; row++) {
      TANGNANO20K_AI_WEIGHT_SEL_REG = row;
      const uint8_t *rowData = bytes + (size_t)row * rowBytes;
      for (size_t i = 0; i < rowBytes; i++)
        TANGNANO20K_AI_WEIGHT_DATA_REG = rowData[i];
    }
  }

  /// `window` is `k*cinPadded` INT8 bytes, `[tap][cinPadded]`, zero-padded
  /// at sequence boundaries. Starts the engine; getResults() blocks until
  /// it's done, no separate delay needed.
  void compute(const int8_t *window, size_t len)
  {
    TANGNANO20K_AI_ACT_RESET_REG = 1;
    const uint8_t *bytes = (const uint8_t *)window;
    for (size_t i = 0; i < len; i++)
      TANGNANO20K_AI_ACT_DATA_REG = bytes[i];
    TANGNANO20K_AI_START_REG = 1;
  }

  /// Reads back `rows*k` raw INT32 dot products (row-major, [row][tap]).
  /// The first read blocks (in hardware) until the engine's `done` fires;
  /// call this right after compute() with no delay in between. `out` must
  /// have room for `rows*k` entries.
  void getResults(int32_t *out, uint8_t rows, uint8_t k)
  {
    uint16_t count = (uint16_t)rows * k;
    for (uint16_t i = 0; i < count; i++) {
      TANGNANO20K_AI_RESULT_ADDR_REG = i;
      out[i] = (int32_t)TANGNANO20K_AI_RESULT_DATA_REG;
    }
  }

private:
  uint16_t cinPadded_ = 0;
  uint8_t k_ = 0;
  uint8_t rows_ = 0;
};

extern AIAcceleratorClass AIAccelerator;
