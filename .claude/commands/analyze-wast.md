# Analyze Wast Command

分析用户提出的 BUG 文件造成的原因，并和用户探讨。

## Input
BUG 文件的路径：$ARGUMENTS 
有可能需要加上前缀 testsuite/data，因为测试用的 wast 文件都在此处

## Workflow

1. **分析问题**：阅读相关代码，分析原因，中途可以询问用户，也可以使用 `./wasmoon explore <file> --stage ir vcode mc` 用于查看编译输出
2. **创建等价的测试**：将造成 bug 的 wast 中，导致问题的函数和断言抽取出来，在 testsuite 目录下创建测试文件，风格参考 @testsuite/fac_test.mbt`

## Notes
- Always create a test first if one doesn't exist
- Run `moon test -p <package-name> -f <filename>` to run the MoonBit tests, e.g. `moon test -p testsuite -f fac_test.mbt`
- Run `./install.sh` before running `./wasmoon` commands
