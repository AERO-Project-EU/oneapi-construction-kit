// Copyright (C) Codeplay Software Limited. All Rights Reserved.

#include "uur/fixtures.h"

using urEnqueueMemBufferReadTest = uur::MemBufferQueueTest;
UUR_INSTANTIATE_DEVICE_TEST_SUITE_P(urEnqueueMemBufferReadTest);

TEST_P(urEnqueueMemBufferReadTest, Success) {
  std::vector<uint32_t> output(count, 42);
  ASSERT_SUCCESS(urEnqueueMemBufferRead(queue, buffer, true, 0, size,
                                        output.data(), 0, nullptr, nullptr));
}

TEST_P(urEnqueueMemBufferReadTest, InvalidNullHandleQueue) {
  std::vector<uint32_t> output(count, 42);
  ASSERT_EQ_RESULT(UR_RESULT_ERROR_INVALID_NULL_HANDLE,
                   urEnqueueMemBufferRead(nullptr, buffer, true, 0, size,
                                          output.data(), 0, nullptr, nullptr));
}

TEST_P(urEnqueueMemBufferReadTest, InvalidNullHandleBuffer) {
  std::vector<uint32_t> output(count, 42);
  ASSERT_EQ_RESULT(UR_RESULT_ERROR_INVALID_NULL_HANDLE,
                   urEnqueueMemBufferRead(queue, nullptr, true, 0, size,
                                          output.data(), 0, nullptr, nullptr));
}

TEST_P(urEnqueueMemBufferReadTest, InvalidNullPointerDst) {
  std::vector<uint32_t> output(count, 42);
  ASSERT_EQ_RESULT(UR_RESULT_ERROR_INVALID_NULL_POINTER,
                   urEnqueueMemBufferRead(queue, buffer, true, 0, size, nullptr,
                                          0, nullptr, nullptr));
}

using urEnqueueMemBufferReadMultiDeviceTest =
    uur::MultiDeviceMemBufferQueueTest;

TEST_F(urEnqueueMemBufferReadMultiDeviceTest, WriteReadDifferentQueues) {
  // First queue does a blocking write of 42 into the buffer.
  std::vector<uint32_t> input(count, 42);
  ASSERT_SUCCESS(urEnqueueMemBufferWrite(queues[0], buffer, true, 0, size,
                                         input.data(), 0, nullptr, nullptr));

  // Then the remaining queues do blocking reads from the buffer. Since the
  // queues target different devices this checks that any devices memory has
  // been synchronized.
  for (unsigned i = 1; i < queues.size(); ++i) {
    const auto queue = queues[i];
    std::vector<uint32_t> output(count, 0);
    ASSERT_SUCCESS(urEnqueueMemBufferRead(queue, buffer, true, 0, size,
                                          output.data(), 0, nullptr, nullptr));
    ASSERT_EQ(input, output) << "Result on queue " << i << " did not match!";
  }
}
