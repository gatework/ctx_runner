# 领域契约与 schema 4 迁移

本轮一次性切换公共接口，不保留旧字段别名。旧报告、变更计划必须重新采集或生成；仅把 schema_version 改为 4 无法补足身份、来源和聚合证据。

## 模块职责

| 模块 | 拥有的领域责任 | 不承担的责任 |
| --- | --- | --- |
| expect-pty | PTY、IO、进程、匹配与终端恢复 | 设备健康、业务策略 |
| net-connector | 会话、登录、操作租约、资产与库存、邻居发现 | 公共观察结论和领域配置验收 |
| ctx_parser | 纯值、解析完整性、命令声明、语法注册 | 连接与报告交付 |
| ctx_driver | 单命令回执、来源摘要、借用会话读写 | 重连、健康判断、厂商配置策略 |
| ctx_runner | Target、Observation、Snapshot、采集交付、配置会话、受控执行 | 厂商语法、资产持久化 |
| ctx_checker | 运行事实、维度身份、健康与覆盖规则 | 配置下发 |
| vxlan | NX-OS、Fabric、配置依赖、可验证变更 | PTY 和公共交付状态机 |
| wireless-rb | AP/Radio/客户端、模板、AP 转接、无线变更 | 公共报告持久性与终端确认 |
| ctx_cli | 配置发现、用户输入输出、宿主入口编排 | 领域身份、采集完整性、网络会话 |

## 公共 Ruby 协议

- `Target.coerce(hash)` 接受明确的公开字段，内部使用 Symbol 键；`host` 必填，其他字段为 `platform/name/model/software_version/id`。对象深度不可变，支持 `with`、相等性、Hash 键和模式匹配。`same_identity?` 只比较 host/platform/id；显示名变化不改变身份。平台由领域 Registry 归一化，采集前拒绝目标与连接平台冲突。
- `Snapshot#target` 返回 Target；`to_h` 投影为普通数据。三个领域都提供 `observations`、`observation(name)`、`records(name)`、`collection_status`、`same_target?`。
- `Observation#evidence` 返回 `CtxDriver::Source` 数组。Source 的核心字段为 command、sha256、bytes、reference、observed_at、status、context；摘要和非负字节数必须同时存在。空 Hash 或仅有时间的来源无效，`not_applicable` 至少需要一份带摘要的来源。
- Source 属性 observed_at 是 UTC Time，`to_h` 将它输出为 ISO8601；领域附加属性放在 context。来源的摘要取自原始输出，不是解析后的正文。时间读取失败不得丢弃已经取得的摘要。
- Checker Observation 继承公共不可变值语义，但每次 `new`/`with` 都重新执行领域字段、身份和状态校验。
- `ConfigurationSession` 借用会话，接受领域注入的准备命令、配置查询和解析器。准备、写入和读取都验证单命令回执；失败不自动重放、不关闭借用会话。领域保留操作租约和前后配置验收。
- 变更对象提供 `to_h`、`commands`、`rollback`、`eligible?`、`satisfied?`；工厂提供 `build`、`candidate`。无线配置索引只构建一次，重复模板名仍是歧义，不能选第一条执行。

## 序列化与字段切换

| 旧接口 | 新接口 |
| --- | --- |
| 报告/计划/执行的 device | target |
| Hash 形式 snapshot.target | Target 值对象，序列化后仍是映射 |
| 任意 Hash 来源附加字段 | Source.context |
| neighbor_name / neighbor_interface / chassis_id | remote_name / remote_interface / remote_chassis_id |
| CDP interface | local_interface |
| BGP peer / peer_ip | peer_address |
| VXLAN BGP address_family: L2VPN EVPN | afi_safi: l2vpn_evpn |
| prefixes_received | received_prefixes |
| BGP 字符串状态 | Symbol 状态，管理关闭为 :shutdown |
| AP 原始状态文本 | :online / :offline / :unknown |
| channel_width / utilization | channel_width_mhz / utilization_percent |
| 无线报告平台 h3c_wireless | h3c |

厂商 CLI 原文和命令名称不改写。Netdisco 的 vendor、连接器凭据命名空间仍保留 h3c_wireless；无线 CLI 在领域平台边界进行映射。Netdisco 资产 Device 仍是资产对象。

schema 4 集合报告的顶层 status 必须与快照实际聚合结果一致；target 与 snapshot.target 的 host/platform/id 必须一致。无快照只能报告 failed。计划的目标平台必须匹配计划平台。Batch 在执行前拒绝重复和未请求目标，返回快照身份不符时不发布其事实。

纯数据和 JSON 使用 128 层深度预算；Fingerprint 不再受 JSON 默认 100 层限制。对象循环、键归一化碰撞和非有限数字仍被拒绝。

## 升级与验证

候选版本：ctx_cli/ctx_driver/ctx_runner 0.5.0，ctx_checker 0.6.0，net-connector 0.21.0，vxlan 0.8.0，wireless-rb 0.9.0。ctx_parser 继续 0.4.0，expect-pty 继续 0.9.6；没有为了统一命名而改动其稳定执行内核。

按 ctx_cli → ctx_driver → ctx_runner → 消费模块更新依赖；net-connector 0.21 依赖 ctx_cli 0.5。Parser 继续使用 0.4 系列。锁文件必须同步，避免把源码联调误当成已安装依赖兼容。

使用 RVM Ruby 4.0.6 执行各仓库 `bundle exec rake`。`script/verify_stack.rb WORKSPACE OUTPUT` 构建九个候选，在临时 GEM_HOME 验证依赖、普通入口、领域 Batch/schema 往返、本地 PTY 和最小 Bundler 消费方。无线 `benchmark/review.rb` 测完整审查序列化，`benchmark/configuration_index.rb` 测候选索引；合成性能不代表实机吞吐或型号认证。
