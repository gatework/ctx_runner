# ctx_runner

网络证据采集、批次交付与受控变更的公共业务库。沿用 ctx_parser 的普通 Ruby 对象、显式参数、不可变快照及独立 gem 工程范式。

## 职责

| 对象 | 负责的业务 |
| --- | --- |
| `SessionScope` | 当前线程内一次会话交付、未完成事实和回调撤销 |
| `Collection` | 一次连接器交付、阶段诊断、禁止重复执行 |
| `Query` | 单命令读取解析、共享视图、失败与来源绑定 |
| `Observation` | 事实外壳、可用性、时间类型、深度快照及安全展示 |
| `Batch` | 单设备结果登记、报告交付、输出失败补写 |
| `Report` | 私有批次目录、文件发布、检查点、完成判定及恢复 |
| `Document` | 有界、无歧义、深冻结的 JSON 值；统一报告和进度交付表示 |
| `Fingerprint` | 稳定配置身份，拒绝归一化键冲突 |
| `Execution` | 已确认增量的前提核验、执行记账、效果不确定状态及回读验收 |

ctx_parser 负责解析事实，ctx_driver 负责借用会话并交付命令 Capture，ctx_runner 负责组织业务过程。厂商语法、健康判定、AP 转接租约和变更规则留在领域模块。连接器拥有连接及关闭，Runner 不隐式连接、重连、提权或重放。

## 使用

Ruby >= 4.0.6。安装后 `require "ctx_runner"`，或按能力加载 `ctx_runner/report` 等文件。加载库不建立网络连接或创建目录。

```ruby
run = CtxRunner::Collection.new
run.open(connector) do |session|
  reader = CtxDriver::Reader.new(session: session)
  query = CtxRunner::Query.new(reader: reader, parser: profile)
  query.read("show example", names: [:example], unavailable: failure_projection) do |name, result, capture|
    CtxRunner::Observation.new(name: name, **result.to_h,
      evidence: capture.evidence, started_at: capture.started_at,
      completed_at: capture.completed_at)
  end
end
# run.failure 是安全的 code/stage/error_type，不包含设备正文或异常消息。
```

领域 Profile 实现 `parse_many(names, body, complete:, command:)`；不可用投影接收 `(name, capture, failure)`。一次 Query 对应一条命令，多个视图共享同一份 Capture。

`Collection.new` 统一记录 session_not_opened/session_reentered，保留首次失败且不重放；strict: 参数已移除。批次快照统一提供 observations Ruby 成员，文档统一使用 observations，采集结论独立为 collection_status，不再生成 :collection 伪观测。交付块未正常完成但异常被连接器吞掉时记录 session_incomplete；跨线程交付记录 session_out_of_scope，并拒绝执行领域块。连接关闭错误不会覆盖已完成的领域事实或先前交付故障。借用会话直接使用 Reader/Query，无需再进入 Collection。

Collection 与 Execution 共用 `SessionScope`。会话必须由创建流程的线程同步交付；并行调度应在每个设备任务内部创建流程。重复交付的异常即使被提供方吞掉，流程仍不能报告完成；所有者退出后保留的回调立即失效。作用域不持有或关闭会话，连接清理仍由连接器负责。跨模块职责、业务原子边界与领域拆分见 [模块设计](docs/module-boundaries.md)。

`Batch.new(report:, progress:, requested:)` 接收报告和进度协作者。`collect(device) { snapshot }` 返回不含原始配置的设备摘要；`run(present:) { ... }` 包住调度和领域后处理；块必须在返回或抛错前回收全部任务。Runner 统一取消、执行失败、报告及输出失败，返回不可变 Completion（status、summary、安全 failure、finalization_error、recovery_failed）。取消优先于收尾失败，展示失败只补写报告、不重采或重复展示。进入收尾即关闭结果登记，run 不可重放。CLI 将 complete/incomplete/failed/interrupted 映射到 0/1/2/130。`finish` 是内部交付步骤；调度和网络资源仍由宿主拥有。

`Report.new(root)` 创建排他的私有批次，目录 0700、文件 0600。`finish(results, requested:) { |summary| text }` 先保存未完成检查点，再发布领域文本，最后发布最终 JSON。`Report::Error#committed?` 区分是否已替换；失败不能被当作可靠发布。`recovery_failed?` 提示恢复也未确认。

`finish` 的展示块、返回摘要与最终 JSON 使用相同的字符串键/状态文档，例如 `summary.fetch("status") == "complete"`；展示回调不能改变这份深冻结快照。`Batch::Completion#status` 仍是符号，`#summary` 是该文档。`progress.result` 与 `progress.finish` 同样接收字符串键文档；`Batch#collect` 的返回值及领域 `report.write` 输入保持 Ruby 设备结果结构。这些交付边界没有符号键兼容分支，旧的 `Report#serializable` 已移除。

最终进度输出发生取消或非局部退出时，Batch 仅补写中断报告，保留已经采集和保存的事实及原退出值，不再调用进度展示或重采设备。普通进度异常记录为输出错误；恢复中的存储异常不会替换最先观察到的退出。

`Document.call(value)` 复制键和值，支持普通 Hash/Array、Time 的 ISO-8601 字符串和 Data 记录，拒绝正规化后的同名键、循环、不透明对象、非有限数以及超过 128 层的嵌套。`checkpoint(relative, value)`、`finalize(relative, value, checkpoint:)` 和 `write_execution(state)` 使用同一转换规则。检查点必须包含非空且不为 `complete` 的状态；最终提交失败只能恢复未完成事实。转换、编码或取消失败也会撤销旧完成结论；撤销文件后的目录同步失败会设置 `recovery_failed?`，原失败仍交还调用者。

`Execution` 只接受宿主已经校验、向用户展示且明确确认的计划。领域 change 实现 `commands`、`eligible?(before)`、`satisfied?(after, before:)`；journal 实现 `write_execution(state)`。每次回调获得快照。发送前保存 pending，发送后保留 acknowledged；失败后的 uncertain 禁止自动重放。`run { |operation| connector.open(&operation) }` 在连接器正常退出后才发布 configuration_verified；这不表示业务健康已验收。

完整可运行离线例子见 [examples](examples)。

## 开发与验证

```sh
bundle install
bundle exec rake
bundle exec rake build
ruby script/verify_package.rb pkg/ctx_runner-0.1.0.gem
```

默认 rake 运行 RSpec、RuboCop 和离线示例。CI 沿用 ctx_parser 的 Ruby 4.0.6 / Linux、macOS 矩阵和固定 action 提交。源码联调在消费仓库显式设置 `CTX_RUNNER_PATH=../ctx_runner`；普通验证使用已安装依赖。首次发版前须先构建安装 runner 候选包再验证消费包。

首个版本为 0.1.0。发布流程复用 CI 制品，验证 GitHub Release 与 RubyGems 下载字节。

模块契约、破坏性迁移与版本矩阵见 [契约迁移](docs/contracts-2026-10-29.md)。
