// Copyright (C) Codeplay Software Limited. All Rights Reserved.

#include "uur/fixtures.h"

using urUSMDeviceAllocTest = uur::QueueTest;
UUR_INSTANTIATE_DEVICE_TEST_SUITE_P(urUSMDeviceAllocTest);

TEST_P(urUSMDeviceAllocTest, Success) {
  void *ptr{nullptr};
  ur_usm_mem_flags_t flags;
  ASSERT_SUCCESS(
      urUSMDeviceAlloc(context, device, &flags, sizeof(int), 0, &ptr));
  ASSERT_NE(ptr, nullptr);

  ur_event_handle_t event = nullptr;
  ASSERT_SUCCESS(
      urEnqueueUSMMemset(queue, ptr, 0, sizeof(int), 0, nullptr, &event));
  EXPECT_SUCCESS(urQueueFlush(queue));
  ASSERT_SUCCESS(urEventWait(1, &event));
  // TODO Make sure memset on device hapenned

  ASSERT_SUCCESS(urMemFree(context, ptr));
  EXPECT_SUCCESS(urEventRelease(event));
}

TEST_P(urUSMDeviceAllocTest, InvalidNullContext) {
  void *ptr{nullptr};
  ur_usm_mem_flags_t flags;
  ASSERT_EQ_RESULT(
      UR_RESULT_ERROR_INVALID_NULL_HANDLE,
      urUSMDeviceAlloc(nullptr, device, &flags, sizeof(int), 0, &ptr));
}

TEST_P(urUSMDeviceAllocTest, InvalidDevice) {
  ur_usm_mem_flags_t flags;
  void *ptr{nullptr};
  ASSERT_EQ_RESULT(
      UR_RESULT_ERROR_INVALID_DEVICE,
      urUSMDeviceAlloc(context, nullptr, &flags, sizeof(int), 0, &ptr));
}

TEST_P(urUSMDeviceAllocTest, InvalidNullPtrFlags) {
  void *ptr{nullptr};
  ASSERT_EQ_RESULT(
      UR_RESULT_ERROR_INVALID_NULL_POINTER,
      urUSMDeviceAlloc(context, device, nullptr, sizeof(int), 0, &ptr));
}

TEST_P(urUSMDeviceAllocTest, InvalidNullPtrResult) {
  ur_usm_mem_flags_t flags;
  ASSERT_EQ_RESULT(
      UR_RESULT_ERROR_INVALID_NULL_POINTER,
      urUSMDeviceAlloc(context, device, &flags, sizeof(int), 0, nullptr));
}
