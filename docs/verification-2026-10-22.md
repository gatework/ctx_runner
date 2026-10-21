# ctx_runner 本地验收（2026-10-22）

## 目标与实现

将重复公共业务流程收敛到独立 gem，沿用 ctx_parser 工程规范。命名使用 Collection、Query、Observation、Batch、Report、Fingerprint、Execution；普通对象组合、显式 require、两空格缩进、中文实现注释、英文 RSpec，复用 CtxParser::Immutable。未引入通用工作流 DSL。

| 范围 | 实现及验收依据 |
| --- | --- |
| 私有证据与完成协议 | Report；report_spec 覆盖目录权限、未完成检查点、不可变摘要、取消及拒绝路径；消费方 report/review specs 验证发布失败和恢复 |
| 受控变更 | Execution/Fingerprint；执行 specs 验证先记账后发送、重复调用、回调失效、发送后日志失败与中断；两方 apply specs 验证漂移、确认、回读失败和领域增量 |
| 采集与来源 | Collection/Query/Observation；唯一会话、关闭失败、共享命令、错误投影与独立快照；三个 collector suites 保留借用会话、覆盖范围和无线 AP 租约 |
| 批量交付 | Batch；保存失败仍保留结果、设备异常隔离、输出失败补写而不重放；消费 CLI suites 验证取消和调度器收尾 |
| 领域边界 | ctx_checker 保留 schema/评估；VXLAN 保留配置顺序和未配置判定；Wireless 保留 AP 作用域与转接；厂商解析器名称不变 |
| 工程 | Rake 默认 RSpec/RuboCop/离线 examples；gemspec 明确包清单；固定 action SHA 的 Linux/macOS CI；隔离安装脚本；README、CHANGELOG、AGENTS |

## 验证记录

Ruby 4.0.6，Bundler 4.0.20。所有命令在各自仓库通过 zsh -ic 执行。

| 仓库 | RSpec | RuboCop | 离线示例与构建 |
| --- | ---: | ---: | --- |
| ctx_runner | 30 / 0 failures | 23 files / 0 offenses | 通过 |
| ctx_checker | 700 / 0 failures | 192 files / 0 offenses | 通过 |
| vxlan | 453 / 0 failures | 106 files / 0 offenses | 通过 |
| wireless | 316 / 0 failures | 91 files / 0 offenses | 通过 |

消费模块分别运行了 `CTX_RUNNER_PATH=../ctx_runner bundle exec rake` 源码联调，以及安装最新 Runner 候选后、不设置该变量的 `bundle install --local`、`bundle exec rake` 和 `bundle exec rake build`。普通入口的完整测试合计 1499 examples，0 failures。源码联调之后 Report 的路径恢复保护又补充了回归；最终普通安装测试使用包含该修复的候选。

Runner 的 `ruby script/verify_package.rb pkg/ctx_runner-0.1.0.gem` 在空 GEM_HOME 安装并运行包内示例。消费模块隔离验证显式传入 Runner 0.1.0、net-connector 0.16.1、expect-pty 0.9.5 候选，精确激活后运行包内示例与 CLI 验证。VXLAN/Wireless 参数顺序为目标、connector、expect、runner；Checker 为目标后跟依赖包（runner、expect、connector）。

独立复核的 Report/Execution/Collection 回归 20 examples、0 failures；已解决摘要所有权、失效回调、替换后取消、初始检查点取消和拒绝路径清理问题。

## 证据边界

本地合成数据及隔离安装证明库契约和普通入口可运行，不表示真实设备认证、远程 CI 已执行或版本已发布。本次不提交、不推送、不发布，也不改变仓库可见性。ctx_parser、ctx_driver、expect-ruby 无变更，net-connector-trunk 原有两份未跟踪设计文档保留。
