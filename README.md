# ctx_runner

网络证据采集、批次交付与受控变更的公共业务库。沿用 ctx_parser 的普通 Ruby 对象、显式参数、不可变快照及独立 gem 工程范式。

## 职责

| 对象 | 负责的业务 |
| --- | --- |
| `Collection` | 一次连接器交付、阶段诊断、禁止重复执行 |
| `Query` | 单命令读取解析、共享视图、失败与来源绑定 |
| `Observation` | 事实外壳、可用性、时间类型、深度快照及安全展示 |
| `Batch` | 单设备结果登记、报告交付、输出失败补写 |
| `Report` | 私有批次目录、文件发布、检查点、完成判定及恢复 |
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

`Collection.new(strict: true)` 对连接器零次/重复回调抛出 ArgumentError，兼容严格宿主契约；默认记录 session_not_opened/session_reentered。连接关闭错误不会覆盖已完成的领域事实。借用会话直接使用 Reader/Query，无需再进入 Collection。

`Batch.new(report:, progress:, requested:)` 接收报告和进度协作者。`collect(device) { snapshot }` 返回不含原始配置的设备摘要；`run(present:) { ... }` 包住调度和领域后处理；块必须在返回或抛错前回收全部任务。Runner 统一取消、执行失败、报告及输出失败，返回不可变 Completion（status、summary、安全 failure、finalization_error、recovery_failed）。取消优先于收尾失败，展示失败只补写报告、不重采或重复展示。进入收尾即关闭结果登记，run 不可重放。CLI 将 complete/incomplete/failed/interrupted 映射到 0/1/2/130。`finish` 是内部交付步骤；调度和网络资源仍由宿主拥有。

`Report.new(root)` 创建排他的私有批次，目录 0700、文件 0600。`finish(results, requested:) { |summary| text }` 先保存未完成检查点，再发布领域文本，最后发布最终 JSON。`Report::Error#committed?` 区分是否已替换；失败不能被当作可靠发布。`recovery_failed?` 提示恢复也未确认。

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
