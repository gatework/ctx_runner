# Report Documents Implementation Plan

> **For agentic workers:** Use executing-plans to implement this plan task-by-task. Preserve unrelated work; no commits, pushes or releases are authorized.

**Goal:** 统一持久化文档与摘要交付，并把输入转换纳入检查点撤销/恢复边界。

**Architecture:** Document 独占 JSON 值正规化；Report 持有发布协议。Batch 和领域报告显式交付/读取字符串键文档，采集结果保持原业务类型。连接器只消费文档，不依赖 Runner。

**Tech Stack:** Ruby 4.0.6、RSpec、Minitest、RuboCop、Rake、本地 gem 安装；连接器保持 Ruby >= 3.4。

**Spec:** ../specs/2026-10-23-report-documents.md

## Global Constraints

- 中文 lib 注释、英文业务字面量；不新增兼容参数或旧入口别名。
- Document 128 层预算；目录 0700、文件 0600；非法路径不执行收尾副作用。
- 不重放设备操作；不把证据/报告完成视为业务健康。
- 保留已有 WIP；不提交、推送或发布。五个隔离工作树从当前真实工作树逐文件复制，最终仅回写本计划修改且原始哈希未变的文件。

## Review Focus

- 输入转换或编码失败/取消发生在第一次 checkpoint 写入之前，旧 complete 必须撤销。
- finalize 的恢复文档含冲突键、循环或 complete，不得提交最终状态或恢复假成功。
- 展示回调改变原结果/诊断对象，文本与 JSON 仍读取已固定的文档。
- 两个字符串键文档在中断时合并 status，不能产生符号/字符串同名键。
- 进度输出失败后重新收尾、未保存但采集完整、非局部退出，不能重复采集或提升完成状态。
- 撤销旧完成文件后的目录同步失败须置 recovery_failed?，不覆盖输入主异常。

## Tasks

### Task 1: Document publication and batch delivery

**Files:** lib/ctx_runner/report.rb、lib/ctx_runner/batch.rb、spec/report_spec.rb、spec/batch_spec.rb、examples/report.rb、README.md、CHANGELOG.md。

**Interfaces:**
- 消费 `Document.call(value)`，返回深冻结字符串键 JSON 值；不新增另一套递归转换器。
- `Report#finish` 的展示块与返回值共享同一文档；`finalize` 返回正规化文档；`checkpoint` 及 `write_execution` 接受可转换文档输入。
- `Batch#collect` 仍返回 Ruby 结果，但向 progress.result 交付 Document；Batch 的 summary 使用字符串键，Completion.status 保持符号。

- [x] **Step 1:** 补实际文件回归：finish 的展示/返回/磁盘内容一致，Time/Data 保留；原输入可变而文档不可变。调整既有摘要断言与 Batch 桩为字符串键；补真实进度文档交付断言。
- [x] **Step 2:** 补 checkpoint/finish/finalize 的循环、冲突键、不透明值、非有限数、超深、编码错误及转换中 throw 的负向输入。断言 ArgumentError 或编码原异常；旧 complete 撤销，已有 incomplete 保留，非法路径不删除外部文件。
- [x] **Step 3:** 补拒绝 complete 恢复文档、中断恢复 status 为 interrupted，以及合法 120 层文档可编码的测试。运行 `bundle exec rspec spec/report_spec.rb spec/batch_spec.rb spec/document_spec.rb`，预期新增行为失败，保存 RED。
- [x] **Step 4:** 删除 serializable；在受保护的 checkpoint 准备范围内构造一次 Document，复用最终文档和检查点 JSON。finalize 预检失败仍撤销旧完成结论；write_execution 同样使用 Document。JSON 编码在已验证文档上关闭重复的较低嵌套限制。更新 Batch 与离线示例。
- [x] **Step 5:** 运行同一聚焦命令并运行完整 `bundle exec rake`，预期零失败；更新接口说明与变更记录。以文件哈希记录代替未授权的 commit。

### Task 2: Consumer migration and actual installation

**Files:** ../ctx_checker/ctx_checker.gemspec、各版本/依赖声明与当前 README；../vxlan/lib/vxlan/cli/report.rb、../wireless/lib/wireless/cli/report.rb、各 spec/cli/report_spec.rb；../net-connector-trunk/lib/net/connector/collect/progress.rb、test/collect_progress_test.rb；各 CHANGELOG.md。

**Interfaces:**
- 两个领域 finish 展示仅从传入的字符串键文档获取设备、状态、待处理和诊断；不再重新读取调用者容器。
- Collect::Progress.result/finish 接收字符串键文档；保留未交付完整证据计失败、部分状态、诊断优先级和待处理/筛除区分。

- [x] **Step 1:** 将消费协议测试输入与期待迁移为文档，运行两个领域 report specs 和连接器 collect_progress_test，确认当前实现无法消费新协议，保存 RED。
- [x] **Step 2:** 同步三个消费者，不添加双键回退；更新 CHANGELOG，运行聚焦测试，预期全部通过。
- [x] **Step 3:** 核对当前源码哈希后，仅把计划文件写回原 checkout；再次执行 Runner、VXLAN、Wireless 的完整默认 rake 及 net-connector 的 script/ci。
- [x] **Step 4:** 构建八个本地候选，逐字节核对包内容，运行普通/Bundler 依赖闭包安装及 CLI/review/实际报告文档验证。未通过不得以源码联调替代。
- [x] **Step 5:** fresh-context 独立审查整个本轮变更；处理实质发现，记录 ruling、测试、打包哈希和仍未验证范围。保留账本，不提交、不删除未提交证据。


## Final verification and rulings

- 普通实际 checkout 门禁：Runner 58、VXLAN 461、Wireless 323、Checker 701；连接器完整 script/ci 1233 runs、12500 assertions，共 2776 项测试。连接器门禁后未改变其生产代码；最终 Runner 修复又完整验证其实际消费者。
- 独立审查找到最终进度 throw 留下 complete；三个真实 CLI 退出回归先失败后通过。修复仅补写报告，不重放采集/进度；无未处理 Critical/Important/Minor。
- JSON 文档接口是明确迁移：Runner 0.2.0、net-connector 0.18.0、VXLAN 0.5.0、Wireless 0.6.0 为本地候选；消费端拒绝旧依赖。Checker 不消费摘要，允许不变的 Runner 0.1/0.2 采集接口；没有双键兼容。
- 五次合成报告发布的 3000 设备中位数：基线 21.709 ms/111171 allocations；首次正规化 25.667 ms/222200；消除逐键数组与重复符号字符串后 17.573 ms/99172。语义断言在计时外，含文件发布 IO；不外推网络收益。
- 全部 WIP 保留，不提交/推送/发布；不删除未提交审查账本。真实设备、断电、远端 CI 及平台矩阵未在本轮执行。完整证据位于工作区 .ctx-report-20261023。
