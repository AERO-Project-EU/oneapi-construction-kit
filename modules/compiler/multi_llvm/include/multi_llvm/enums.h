// Copyright (C) Codeplay Software Limited
//
// Licensed under the Apache License, Version 2.0 (the "License") with LLVM
// Exceptions; you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://github.com/codeplaysoftware/oneapi-construction-kit/blob/main/LICENSE.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations
// under the License.
//
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifndef MULTI_LLVM_ENUMS_H_INCLUDED
#define MULTI_LLVM_ENUMS_H_INCLUDED

#include <llvm/Support/CodeGen.h>
#include <multi_llvm/llvm_version.h>

namespace multi_llvm {
#if LLVM_VERSION_MAJOR >= 18

typedef llvm::CodeGenFileType CodeGenFileType;
typedef llvm::CodeGenOptLevel CodeGenOptLevel;

#else

struct CodeGenFileType {
  static constexpr auto AssemblyFile = llvm::CGFT_AssemblyFile;
  static constexpr auto ObjectFile = llvm::CGFT_ObjectFile;
  static constexpr auto Null = llvm::CGFT_Null;
};

struct CodeGenOptLevel {
  static constexpr auto None = llvm::CodeGenOpt::None;
  static constexpr auto Less = llvm::CodeGenOpt::Less;
  static constexpr auto Default = llvm::CodeGenOpt::Default;
  static constexpr auto Aggressive = llvm::CodeGenOpt::Aggressive;
};

#endif
}  // namespace multi_llvm

#endif  // MULTI_LLVM_ENUMS_H_INCLUDED