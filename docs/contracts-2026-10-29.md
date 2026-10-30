# 九模块契约与迁移

> Historical schema 3 review. Current contracts and migration: [2026-10-30](contracts-2026-10-30.md).

此次改动以实际调用链和既有故障测试为依据。保持九个 gem，不新增公共工具 gem；厂商语法、AP 租约、Fabric 范围及健康规则仍由对应领域维护。

## 质量审查结论

| 模块 | 主要结论 | 本次处理 |
| --- | --- | --- |
| expect-pty（仓库 expect-ruby） | IO/PID 所有权、超时、脱敏和回收已有独立边界 | 保留实现，验证 PTY、资源关闭和独立安装 |
| net-connector | 已有独占会话与 Credentials；消费端 apply 重复凭据逻辑；归档投递可能漏检同一时钟粒度内的源文件覆写 | 复用 Credentials，限定依赖区间；投递后在原描述符上再次核对大小与摘要 |
| ctx_parser | ScopedResult 在消费端另行定义值语义；命令校验散落多处 | Result 正式包含 covered_scopes；统一 command_text 和严格时刻解析 |
| ctx_driver | 借用会话、单命令回执边界清晰 | 使用公共命令校验，保留失同步后停止和不重连契约 |
| ctx_runner | 三个领域的快照聚合与 Batch 不一致；关闭失败可能遮盖被吞掉的回调失败 | 公共 Snapshot/Target，独立 collection_status，保留最初失败 |
| ctx_cli | 两套 apply 重复校验和、确认、错误处理和执行编排 | 注入领域 adapter 与执行器的 Apply；无 Runner/连接器依赖 |
| ctx_checker | 严格领域校验有价值，但公共值与时间接口分叉 | 组合公共 Observation/Snapshot，保留身份、字段和覆盖校验 |
| VXLAN | OSPF 字段与 Checker 同义不同名；快照接收任意身份字段 | 统一公共字段和快照；保留 Fabric/ACL/ChangePlan |
| Wireless | 未知维度与已知不支持维度混淆；计划缺少统一选择和校验和 | 未知维度报错，已知不支持保留 unsupported；并发收集后稳定汇总具名计划 |

完整采集、语法覆盖、领域健康、设备变更效果和报告持久性是不同事实。此次统一接口不把它们合并成单一 success。

## 对象契约

- `CtxParser::Result` 是深度不可变的 Data 值：`status, records, issues, covered_scopes`。默认 scopes 为 `[]`，参与 `==`、`eql?`、`hash`、`with`、模式匹配和 `to_h`；不再使用 ScopedResult。
- `CtxParser::Commands.command_text(value)` 接受非空、无控制字符的单行 String，返回独立冻结文本。Profile、Driver、Query 和 Execution 共用该边界。
- `CtxParser::Values.timestamp(value)` 接受含明确时区的 ISO8601 文本，拒绝日期、时分秒和时区越界，返回 UTC Time。
- `Observation` 的公共字段为 `name, status, records, issues, evidence, started_at, completed_at, covered_scopes`。采集时间为 Time 或 nil；`observed_at` 从来源 evidence 的时刻得出，不能用报告时间替代。
- Checker 组合公共 Observation，再约束领域字段、记录身份和 scope；VXLAN/Wireless 保留公开 Observation 类型。不会冻结调用方对象。
- `Snapshot` 提供 `target, observations, observed_at, issues, collection_status, observation(name), complete?, same_target?, to_h`。领域通过组合声明允许的维度；未知维度或键值名称不一致立即报错。
- `target` 只允许 `host, platform, name, model, software_version, id`；String/Symbol 键归一为 Symbol，拒绝重复、未知字段和控制字符。host 必须有值；id 可为文本或非负整数。密码、连接选项及任意属性不可进入身份。
- Snapshot 的 `observed_at` 必须是 Time。Ruby `to_h` 保留类型；JSON 必须经 `CtxRunner::Document.call`，统一为 UTC ISO8601（六位小数）。

Observation 状态包括 complete、partial、failed、unsupported、not_requested、not_applicable。不可用状态不能带 records；not_applicable 必须携带来源证据。

| 所请求的观测 | collection_status |
| --- | --- |
| 无请求或全部 not_requested，且无采集错误 | not_requested |
| 有请求，但既无可用事实，也无有证据的不适用结论 | failed |
| 全部 complete 或有证据的 not_applicable，且无采集错误 | complete |
| 部分事实、部分失败或已取得事实后关闭失败 | partial |

不再创建 `observations[:collection]`。Batch 从 `snapshot.collection_status` 取结论；`snapshot.issues` 保存会话层诊断。Batch 摘要的 `dimensions` 是按维度计数的摘要，并非 Snapshot 字段别名。

VXLAN OSPF 使用 `process_id, vrf, router_id, neighbor_address, interface, state, neighbor_role`；state 为 Symbol（如 `:full`、`:two_way`），角色独立为 `:dr/:bdr/:drother/:unknown`。原有 priority 和 uptime 继续保留。厂商命令文件名与解析入口不变。

## 文件格式与 apply

两个领域 CLI 的新报告/计划使用 `schema_version: 3` 和明确的 `kind`：collection、batch、recommendations、review、fabric_review、change_plan、change、execution。离线 review/apply 拒绝旧版本；请重新采集、重新生成计划，不用字段猜测或手工只改版本号。

collection 的 snapshot 使用 `observations` 和独立 `collection_status`。读取端同时核对身份、维度、时间、状态及聚合结论，领域记录交由领域 adapter 验证。

两个领域都输出 `plan.json`，结构为 `kind: change_plan, platform, changes: { ID => change }`。每项 change 绑定设备、完整配置指纹、类型化增量及重新生成的 commands/rollback；相邻的 `plan.json.sha256` 绑定文件内容。checksum 只检测内容变化，不是签名或授权。

```sh
vxlan apply --plan plan.json --item CHANGE_ID
wireless apply --plan plan.json --item CHANGE_ID
```

必须显式选一项；终端确认绑定 host、计划摘要和 item。确认后经 Credentials 解析平台优先/通用回退凭据，再创建执行日志、回读前置配置、逐条记账和回读验收。失败后不重放、不自动回退、不保存 startup 配置。执行成功仍需要业务验收。

`CtxCli::Apply` 的 adapter 提供 `select_plan(document, item:)`、`validate_plan(plan)`、`credentials(options)`、`report(options)`、`with_session(device, settings)`。注入的 execution 实现 `run`、`started?`、`journal_failed?`。CLI 不解释厂商命令或业务健康。

## 版本及验证入口

| gem | 候选版本 | Ruby 下限 |
| --- | --- | --- |
| expect-pty | 0.9.6（实现未改） | 3.4 |
| net-connector | 0.20.0 | 3.4 |
| ctx_cli | 0.4.0 | 3.4 |
| ctx_parser / ctx_driver / ctx_runner | 0.4.0 | 4.0.6 |
| ctx_checker | 0.5.0 | 4.0.6 |
| vxlan | 0.7.0 | 4.0.6 |
| wireless-rb | 0.8.0 | 4.0.6 |

依赖按支持的下一个 minor 设上界。使用 RVM 安装和选择运行时，例如 `rvm install ruby-4.0.6`、`rvm use ruby-4.0.6`；3.4 库另用 3.4 分支验证。

每个仓库先运行自己的 Bundler 检查；跨仓库源码联调与普通安装分别验证。工作区目录名须与下列脚本声明一致：

```sh
ruby ctx_runner/script/verify_stack.rb /absolute/workspace /absolute/artifacts
```

脚本构建九个候选，校验全部依赖边，将运行依赖缓存和候选装进临时 GEM_HOME，禁止源码路径进入消费环境，执行三个领域的 Batch/schema 往返、离线示例、普通 CLI 和真实 PTY，再通过最小 Bundler 消费方重复验证。manifest.json 记录源提交、候选版本与 SHA256。未提交改动以候选包摘要确定内容，不将基线提交冒充最终源码提交。

单机离线测试不等于 macOS 或网络设备型号验证；未实际运行的环境不列为通过。
