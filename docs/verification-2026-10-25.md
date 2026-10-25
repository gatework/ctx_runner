# 2026-10-25 模块边界重构验证

本次代码改动集中于 ctx_runner 的 SessionScope/Collection/Execution 和 Wireless 的 ApCollection/Collector。模块设计见 [module-boundaries.md](module-boundaries.md)。工作区已有大量未提交改动，本记录只评价本次重构及相关链路，不替代各仓库完整发布验证。

## 已通过

| 检查 | 结果 | 范围 |
| --- | --- | --- |
| 关键回归前后对照 | 原实现 3 项失败；修改后 3 项通过 | 提供方吞掉未完成异常、严格模式重复交付、变更执行重复交付 |
| 跨模块业务契约 | 18/18 通过 | 会话作用域、执行记账、VXLAN、Wireless、AP 选择/覆盖和 ctx_checker 共享查询 |
| net-connector 定向测试 | 69 tests / 664 assertions，通过 | execution_receipts、engine_boundary、transport |
| expect-pty 定向测试 | 35 tests / 225 assertions，通过 | cleanup、cleanup_priority、resource_acquisition |
| 现有离线与本地 PTY 示例 | 9 个通过 | ctx_parser 1、ctx_driver 2、ctx_runner 2、ctx_checker 2、VXLAN 1、Wireless 1 |
| 修改文件语法 | 10 个 Ruby 文件通过 | 生产代码及新增/修改的 RSpec 文件 |
| 按能力独立加载 | 通过 | `require "wireless/ap_collection"` 未加载 net-connector |
| 差异格式 | 通过 | ctx_runner、Wireless 的 `git diff --check` |

Driver 与 Checker 的 connector 示例使用真实 expect-pty、net-connector、Driver 和解析器驱动本地合成 PTY。没有连接真实设备，不声明所有厂商型号兼容性。

## 环境与限制

环境初始没有 Ruby；从工作区已有 Ruby 4.0.7 源码构建了 Linux x86_64 验证运行时。安装遗漏的 `digest/sha2/loader.rb` 从同一源码补入测试运行时，未修改项目业务实现。由于缺少 libyaml，Psych 未构建。

底层定向测试使用工作区缓存的 Minitest 源码，源码 `VERSION=5.26.2`，缓存目录和 gem specification 标为 5.27.0。明确激活该缓存并设置 `MT_NO_PLUGINS=1`，避免内置 Minitest 6 的插件再次加载并清空测试注册。最终记录均核对了非零 test/assertion 数；总计 104 tests、889 assertions，0 failures、0 errors、0 skips。这属于本地兼容性验证，不是锁定依赖矩阵通过。

下列检查尚未完成：

- ctx_runner 和 Wireless 的 `bundle exec rake`：以 frozen 模式运行时，分别被现有锁文件 ctx_parser/ctx_cli 的空 CHECKSUMS 项阻止；未修改锁文件。环境还缺少 RSpec 和项目完整依赖。
- 新增 RSpec 回归已写入对应仓库，并完成语法校验；上述独立契约检查覆盖了关键行为，但不等于 RSpec 全量运行。
- ctx_cli 的两个示例、VXLAN 的 collect/parse CLI 示例：因缺少 Psych/YAML 不能完成。
- 两个改动包的 `gem build`：因缺少 Psych 失败，因此尚未执行隔离 gem 安装验证。
- 完整 RuboCop、Ruby 版本/操作系统矩阵及实机验收尚未运行。RubyGems 域名在当前环境无法解析，不能补齐缺失依赖。

## 证据与复现

本地脚本与日志保存在工作区 `.module-validation-20261025/`：

- `verify.rb` / `logs/contracts.json`：18 项源码联调。
- `regressions.rb` / `logs/regressions-before.json` / `logs/regressions-after.json`：3 项缺陷前后对照。
- `check-native.py` / `logs/native-tests.json`：底层定向测试及计数。
- `check-examples.py` / `logs/examples.json`：示例逐项退出码。
- `logs/syntax.json`：语法校验；其余 log 保存构建、Bundler 和示例诊断。

为避免重新堆积大型临时文件，完成验证后删除本次创建的编译目录和测试运行时；保留脚本及日志。需要重建时可在工作区根目录执行 `sh .module-validation-20261025/build-runtime.sh`，并补齐 libyaml/Psych、RSpec 和锁定依赖，再运行各仓库完整 gate、构建和隔离安装验证。源码联调脚本使用显式 RUBYLIB，不修改 gemspec 的安装边界。
