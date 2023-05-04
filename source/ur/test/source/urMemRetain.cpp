// Copyright (C) Codeplay Software Limited. All Rights Reserved.

#include "uur/fixtures.h"

using urMemRetainTest = uur::MemBufferTest;
UUR_INSTANTIATE_DEVICE_TEST_SUITE_P(urMemRetainTest);

TEST_P(urMemRetainTest, Success) {
  ASSERT_SUCCESS(urMemRetain(buffer));
  EXPECT_SUCCESS(urMemRelease(buffer));
}

TEST_P(urMemRetainTest, InvalidNullHandleMem) {
  ASSERT_EQ_RESULT(UR_RESULT_ERROR_INVALID_NULL_HANDLE, urMemRetain(nullptr));
}
